import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui show instantiateImageCodec, Codec;

import 'package:disk_lru_cache/_src/ioutil.dart';
import 'package:disk_lru_cache/_src/lock.dart';
import 'package:disk_lru_cache/_src/lru_map.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:http/http.dart' as http;

///
const _ = null;

///
class DiskLruCache implements Closeable {
  static const MAGIC = "dart.lrucache";
  static const VERSION = "0.0.1";
  static const ANY_SEQUENCE_NUMBER = -1;

  static const READ = "READ";
  static const DIRTY = "DIRTY";
  static const CLEAN = "CLEAN";
  static const REMOVE = "REMOVE";

  static const MAX_OP_COUNT = 2000;

  /// Record every operation in this file.
  final File _recordFile;

  final int opCompactThreshold;

  /// Used when rebuild record file if necessary
  final File _recordFileTmp;

  final File _recordFileBackup;

  /// directory to store caches
  final Directory directory;

  /// The maximum number of bytes that this cache should use to store its data.
  final int maxSize;

  /// How many files a key/CacheEntry contains?
  final int _filesCount;

  /// store entries in memory,so that we can find our cache quickly
  final LruMap<String, CacheEntry> _lruEntries;

  int _opCount = 0;

  bool _initialized = false;
  bool _hasRecordError = false;

  bool _closed = false;

  /// Cache size in bytes
  int _size = 0;

  int get size => _size;

  bool _mostRecentTrimFailed = false;

  /// IOSink for record file
  IOSink _recordWriter;

  int _sequenceNumber = 0;

  DiskLruCache(
      {Directory directory,
      this.maxSize: 20 * 1024 * 1024,
      int filesCount: 2,
      this.opCompactThreshold: MAX_OP_COUNT})
      : assert(directory != null),
        this.directory = directory,
        _filesCount = filesCount,
        _lruEntries = new LruMap(),
        _recordFile = new File("${directory.path}/record"),
        _recordFileTmp = new File("${directory.path}/record.tmp"),
        _recordFileBackup = new File("${directory.path}/record.bak");

  /// Returns a snapshot of the entry named key, or null if it doesn't exist is not currently
  /// readable. If a value is returned, it is moved to the tail of the LRU queue.
  Future<CacheSnapshot> get(String key) {
    return SynchronizedLock.synchronized<CacheSnapshot>(this, () async {
      await _lazyInit();
      CacheEntry entry = _lruEntries[key];
      if (entry == null || !entry.ready) {
        return _;
      }

      CacheSnapshot snapshot = await entry.snapshot();
      if (snapshot == null) {
        return null;
      }

      await _recordRead(key);

      return snapshot;
    });
  }

  Future clean() {
    return SynchronizedLock.synchronized(this, () async {
      Iterable<CacheEntry> entries = await values;
      List<Future<bool>> list = [];
      for (CacheEntry entry in entries) {
        list.add(remove(entry.key));
      }
      return await Future.wait(list);
    });
  }

  Future<CacheEditor> edit(String key,
      {int sequenceNumber: ANY_SEQUENCE_NUMBER}) {
    return SynchronizedLock.synchronized<CacheEditor>(this, () async {
      await _lazyInit();

      CacheEntry entry = _lruEntries[key];

      if ((entry == null || entry.sequenceNumber != sequenceNumber) &&
          sequenceNumber != ANY_SEQUENCE_NUMBER) {
        //the cache is stale
        return null;
      }
      if (entry != null && entry.currentEditor != null) {
        return null; // Another edit is in progress.
      }

      //Flush the record before creating files to prevent file leaks.
      await _recordDirty(key);

      if (entry == null) {
        entry = new CacheEntry(
          key: key,
          cache: this,
        );
        _lruEntries[key] = entry;
      }

      CacheEditor editor = new CacheEditor._(entry: entry, cache: this);
      entry.currentEditor = editor;
      return editor;
    });
  }

  Future _recordRead(String key) async {
    ++_opCount;
    _recordWriter.write("$READ $key\n");
    await _recordWriter.flush();
    if (_needsRebuild()) {
      await _cleanUp();
    }
  }

  Future _recordDirty(String key) async {
    ++_opCount;
    _recordWriter.write("$DIRTY $key\n");
    await _recordWriter.flush();
    if (_needsRebuild()) {
      await _cleanUp();
    }
  }

  Future _recordClean(String key, List<int> lengths) async {
    ++_opCount;
    _recordWriter.write("$CLEAN $key");
    for (int length in lengths) {
      _recordWriter.write(" $length");
    }
    _recordWriter.write("\n");
    await _recordWriter.flush();
    if (_needsRebuild() || _size > maxSize) {
      await _cleanUp();
    }
  }

  Future _recordRemove(String key) async {
    ++_opCount;
    _recordWriter.write("$REMOVE $key\n");
    await _recordWriter.flush();
    if (_needsRebuild()) {
      await _cleanUp();
    }
  }

  /// We only rebuild record file when opCount is at least MAX_OP_COUNT
  bool _needsRebuild() {
    return _opCount >= opCompactThreshold && _opCount >= _lruEntries.length;
  }

  Future _trimToSize() async {
    while (_size > maxSize) {
      CacheEntry toEvict = _lruEntries.removeHead();
      await _removeEntry(toEvict);
    }
    _mostRecentTrimFailed = false;
  }

  Future _cleanUp() {
    return SynchronizedLock.synchronized(this, () async {
      try {
        print("Start cleanup");
        await _trimToSize();
        if (_needsRebuild()) {
          await _rebuildRecord();
        }
        print("Cleanup success");
      } catch (e) {
        print("Cleanup failed! $e");
      }
    });
  }

  Future _rebuildRecord() {
    return SynchronizedLock.synchronized(this, () async {
      print("Start to rebuild record");
      if (_recordWriter != null) {
        await _recordWriter.close();
      }

      if (!await this.directory.exists()) {
        await this.directory.create(recursive: true);
      }

      IOSink writer = _recordFileTmp.openWrite();
      try {
        // write headers
        writer.write("$MAGIC\n$VERSION\n$_filesCount\n\n");
        //write entries
        for (CacheEntry entry in _lruEntries.values) {
          entry._writeTo(writer);
        }
        await writer.flush();
      } catch (e) {
        print("Cannot write file at this time $e");
        return _;
      } finally {
        try {
          await writer.close();
        } catch (e) {
          print("Cannot write file at this time $e");
          return _;
        }
      }

      if (await _recordFile.exists()) {
        await _recordFile.rename(_recordFileBackup.path);
      }

      await _recordFileTmp.rename(_recordFile.path);
      await _deleteSafe(_recordFileBackup);

      _recordWriter = _newRecordWriter();
      _hasRecordError = false;

      print("Rebuild record success!");
    });
  }

  ///
  IOSink _newRecordWriter() {
    return new IOSinkProxy(_recordFile.openWrite(mode: FileMode.append),
        onError: (e) async {
      _hasRecordError = true;
      //_rebuildRecord();
    });
  }

  /// Read record file, rebuild it if broken.
  Future _lazyInit() {
    return SynchronizedLock.synchronized(this, () async {
      if (_initialized) {
        return _;
      }
      if (!await this.directory.exists()) {
        await this.directory.create(recursive: true);
      }

      // If a bkp file exists, use it instead.
      if (await _recordFileBackup.exists()) {
        // If recod file also exists just delete backup file.
        if (await _recordFile.exists()) {
          await _recordFileBackup.delete();
        } else {
          _recordFileBackup.rename(_recordFile.path);
        }
      }

      if (await _recordFile.exists()) {
        try {
          await _parseRecordFile();
          await _processRecords();
          _initialized = true;
          return _;
        } catch (e) {
          print("DiskLruCache error when init $e");
          try {
            await _deleteCache();
          } catch (e) {}
        }
      }
      await _rebuildRecord();
      _initialized = true;
    });
  }

  Future _deleteCache() async {
    await close();
    await directory.delete(recursive: true);
  }

  /// make copy of current values
  Future<Iterable<CacheEntry>> get values {
    return SynchronizedLock.synchronized(this, () async {
      await _lazyInit();
      return List<CacheEntry>.from(_lruEntries.values);
    });
  }

  Future _parseRecordFile() async {
    try {
      List<String> lines = await _recordFile.readAsLines();
      if (lines.length < 4) {
        throw new Exception("The record file is broken: Too small to parse");
      }
      String magic = lines[0];
      String version = lines[1];
      String filesCountString = lines[2];
      String blank = lines[3];

      if (magic != MAGIC ||
          version != VERSION ||
          filesCountString != this._filesCount.toString() ||
          blank != '') {
        throw new Exception(
            "The record file is broken: unexpected file header:[$magic,$version,$filesCountString,$blank]");
      }

      int lineCount = 0;
      for (int i = 4, c = lines.length; i < c; ++i) {
        _parseRecordLine(lines[i]);
        ++lineCount;
      }

      _opCount = lineCount - _lruEntries.length;

      _recordWriter = _newRecordWriter();
    } catch (e) {
      print(e);
      rethrow;
    }
  }

  void _parseRecordLine(String line) {
    int firstSpace = line.indexOf(' ');
    if (firstSpace == -1) {
      throw new Exception("unexpected record line: " + line);
    }

    int keyBegin = firstSpace + 1;
    int secondSpace = line.indexOf(' ', keyBegin);
    String key;
    if (secondSpace == -1) {
      key = line.substring(keyBegin);
      if (firstSpace == REMOVE.length && line.startsWith(REMOVE)) {
        _lruEntries.remove(key);
        return;
      }
    } else {
      key = line.substring(keyBegin, secondSpace);
    }

    CacheEntry entry = _lruEntries[key];
    if (entry == null) {
      entry = new CacheEntry(
        key: key,
        cache: this,
      );
      _lruEntries[key] = entry;
    }

    if (secondSpace != -1 &&
        firstSpace == CLEAN.length &&
        line.startsWith(CLEAN)) {
      List<String> parts = line.substring(secondSpace + 1).split(" ");
      entry.ready = true;
      entry.currentEditor = null;
      entry
          .setLengths(parts.map((String length) => int.parse(length)).toList());
    } else if (secondSpace == -1 &&
        firstSpace == DIRTY.length &&
        line.startsWith(DIRTY)) {
      entry.currentEditor = new CacheEditor._(entry: entry, cache: this);
    } else if (secondSpace == -1 &&
        firstSpace == READ.length &&
        line.startsWith(READ)) {
      // This work was already done by calling lruEntries.get().
    } else {
      throw new Exception("unexpected journal line: " + line);
    }
  }

  /// Close the cache, do some clean stuff, it is an error to use cache when cache is closed.
  @override
  Future close() {
    return SynchronizedLock.synchronized(this, () async {
      if (_closed) return _;
      try {
        if (_recordWriter != null) {
          await _recordWriter.close();
          _recordWriter = null;
        }
      } finally {
        _closed = true;
        _initialized = false;
      }
      print("Cache is closed");
      return _;
    });
  }

  Future<bool> remove(String key) {
    return SynchronizedLock.synchronized<bool>(this, () async {
      await _lazyInit();
      CacheEntry entry = _lruEntries[key];
      if (entry == null) return false;
      await _removeEntry(entry);
      return true;
    });
  }

  /// Error when read the cache stream, the cache must be removed
  void _onCacheReadError(String key, e) {
    remove(key);
  }

  Future _processRecords() async {
    await _deleteSafe(_recordFileTmp);

    List<CacheEntry> list = List.of(_lruEntries.values);
    int size = 0;
    for (CacheEntry entry in list) {
      if (entry.currentEditor == null) {
        for (int t = 0; t < _filesCount; t++) {
          size += entry.lengths[t];
        }
      } else {
        entry.currentEditor = null;
        for (int t = 0; t < _filesCount; t++) {
          await _deleteSafe(entry.cleanFiles[t]);
          await _deleteSafe(entry.dirtyFiles[t]);
        }
        _lruEntries.remove(entry.key);
      }
    }

    _size = size;
  }

  Future _deleteSafe(File file) async {
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (e) {
        //if the file cannot be deleted,may be OS errors.
      }
    }
  }

  /// clean the entry,remove from cache
  Future _rollback(CacheEditor editor) {
    return SynchronizedLock.synchronized(this, () async {
      CacheEntry entry = editor.entry;
      entry.currentEditor = null;
      await Future.wait(entry.dirtyFiles.map(_deleteSafe));

      if (entry.ready) {
        await _recordClean(entry.key, entry.lengths);
      } else {
        await _recordRemove(entry.key);
      }
    });
  }

  Future _complete(CacheEditor editor) async {
    try {
      await _commit(editor);
    } catch (e) {
      print("Error $e when commit $editor");
      await _rollback(editor);
    }
  }

  Future _commit(CacheEditor editor) {
    return SynchronizedLock.synchronized(this, () async {
      CacheEntry entry = editor.entry;
      if (entry.currentEditor != editor) {
        throw new Exception("Commit editor's entry did not match the editor");
      }

      if (!entry.ready) {
        if (!editor.hasValues.every((bool value) => value)) {
          _rollback(editor);
          return _;
        }
        for (File file in editor.entry.dirtyFiles) {
          if (!await file.exists()) {
            _rollback(editor);
            return _;
          }
        }
      }
      int index = 0;
      for (File dirty in editor.entry.dirtyFiles) {
        File clean = entry.cleanFiles[index];
        await dirty.rename(clean.path);
        int oldLength = entry.lengths[index];
        int newLength = await clean.length();
        entry.lengths[index] = newLength;
        _size = _size - oldLength + newLength;
        ++index;
      }

      entry.sequenceNumber = _sequenceNumber++;

      entry.ready = true;
      entry.currentEditor = null;

      await _recordClean(entry.key, entry.lengths);
    });
  }

  Future _removeEntry(CacheEntry entry) async {
    if (entry.currentEditor != null) {
      // Prevent the edit from completing normally.
      entry.currentEditor.detach();
    }

    for (int i = 0; i < _filesCount; i++) {
      await _deleteSafe(entry.cleanFiles[i]);
      _size -= entry.lengths[i];
      entry.lengths[i] = 0;
    }
    await _recordRemove(entry.key);
    return true;
  }
}

class CacheEditor {
  final CacheEntry entry;

  final DiskLruCache cache;
  // If a cache is first created, it must has value for all of the files.
  final List<bool> hasValues;

  ///
  bool _done = false;

  CacheEditor._({this.entry, this.cache})
      : assert(entry != null),
        assert(cache != null),
        hasValues = new List(cache._filesCount)
          ..fillRange(0, cache._filesCount, false);

  Future detach() {
    return SynchronizedLock.synchronized(this, () async {
      if (entry.currentEditor == this) {
        for (int i = 0, c = cache._filesCount; i < c; i++) {
          await cache._deleteSafe(entry.dirtyFiles[i]);
        }
        entry.currentEditor = null;
      }
    });
  }

  @override
  String toString() {
    return "Editor {key: ${entry.key}, done: $_done}";
  }

  Future commit() async {
    return SynchronizedLock.synchronized(cache, () async {
      if (_done) {
        return;
      }
      if (entry.currentEditor == this) {
        await cache._complete(this);
      }
      _done = true;
    });
  }

  ///
  /// Return a stream that copy it's data to IOSink when read
  ///
  Future<Stream<List<int>>> copyStream(
      int index, Stream<List<int>> stream) async {
    IOSink sink = await newSink(index);
    return new CloseableStream(stream, onData: (List<int> data) {
      sink.add(data);
    }, onDone: () {
      sink.close();
    }, onError: (e) {
      sink.addError(e);
    });
  }

  Future<IOSink> newSink(int index) {
    return SynchronizedLock.synchronized<IOSink>(cache, () {
      if (_done) {
        throw new Exception("The editor is finish done it's job");
      }

      if (entry.currentEditor != this) {
        return new EmptyIOSink();
      }

      if (!entry.ready) {
        hasValues[index] = true;
      }

      File dirtyFile = entry.dirtyFiles[index];
      // this sink do not throw exception
      return new IOSinkProxy(dirtyFile.openWrite(), onError: (e) async {
        print("Error when write to disk cache");
        await detach();
      });
    });
  }
}

class CacheEntry {
  final List<File> cleanFiles;
  final List<File> dirtyFiles;
  final List<int> lengths;

  CacheEditor currentEditor;

  // This value is true when all the files in this entry can be read.
  bool ready = false;

  final String key;

  final DiskLruCache cache;

  int sequenceNumber;

  CacheEntry({this.key, this.cache, this.sequenceNumber})
      : cleanFiles = new List(cache._filesCount),
        dirtyFiles = new List(cache._filesCount),
        lengths = new List(cache._filesCount) {
    // The names are repetitive so re-use the same builder to avoid allocations.
    for (int i = 0; i < cache._filesCount; i++) {
      cleanFiles[i] = new File("${cache.directory.path}/$key.$i");
      dirtyFiles[i] = new File("${cache.directory.path}/$key.$i.tmp");

      this.lengths[i] = 0;
    }
  }

  int get size {
    int _size = 0;
    for (int i = 0, c = lengths.length; i < c; ++i) {
      _size += lengths[i];
    }
    return _size;
  }

  String toString() {
    return "CacheEntry{key:$key}";
  }

  void _onStreamError(e) {
    this.cache._onCacheReadError(key, e);
  }

  void setLengths(List<int> lengths) {
    List.writeIterable(this.lengths, 0, lengths);
  }

  Future<CacheSnapshot> snapshot() async {
    int filesCount = cache._filesCount;
    List<CloseableStream<List<int>>> streams = new List(filesCount);
    for (int i = 0; i < filesCount; ++i) {
      if (await cleanFiles[i].exists()) {
        try {
          streams[i] = new CloseableStream(cleanFiles[i].openRead(),
              onError: _onStreamError);
        } catch (e) {
          print("Open file read error $e");
          return null;
        }
      } else {
        await Future.wait(cleanFiles.map(cache._deleteSafe));
        //File not found,then the cache is not exists,remove this cache
        this.cache._onCacheReadError(
            key, new FileSystemException("File [${cleanFiles[i]}] not found"));
        return null;
      }
    }
    try {
      return new CacheSnapshot(streams: streams, lengths: lengths, key: key);
    } catch (e) {
      print(e);
      rethrow;
    }
  }

  void _writeTo(IOSink writer) {
    if (currentEditor != null) {
      writer.write("${DiskLruCache.DIRTY} $key\n");
    } else {
      writer.write("${DiskLruCache.CLEAN} $key");
      for (int length in lengths) {
        writer.write(" $length");
      }
      writer.write("\n");
    }
  }
}

///
class CacheSnapshot implements Closeable {
  final List<CloseableStream<List<int>>> streams;
  final List<int> lengths;
  final String key;
  CacheSnapshot(
      {this.key, List<CloseableStream<List<int>>> streams, this.lengths})
      : assert(
            streams != null && streams.length > 0, "Streams is null or empty"),
        streams = List.unmodifiable(streams);

  Future<Uint8List> getBytes(int index) async {
    return new http.ByteStream(getStream(index)).toBytes();
  }

  @override
  String toString() {
    return "CacheSnapshot:{count:${lengths.length}, key:$key}";
  }

  Future<String> getString(int index, {Encoding encoding: utf8}) {
    return IoUtil.stream2String(getStream(index), encoding);
  }

  Stream<List<int>> getStream(int index) {
    assert(index >= 0 && index < streams.length);
    return streams[index];
  }

  @override
  Future close() {
    List<Future> list = [];
    for (CloseableStream<List<int>> stream in streams) {
      list.add(stream.close());
    }
    return Future.wait(list);
  }
}
