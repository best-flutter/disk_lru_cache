import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:disk_lru_cache/_src/disk_lru_cache.dart';
import 'package:http/http.dart';
import 'package:test/test.dart';
import 'dart:math' as Math;
import 'package:disk_lru_cache/disk_lru_cache.dart';

void main() {
  int maxSize =
      10 * 1024 * 1024; // 10M,make sure to test rebuild progress below

  Directory cacheDirectory =
      new Directory("${Directory.systemTemp.path}/cache");

  test("Basic usage with bytes", () async {
    DiskLruCache cache = new DiskLruCache(
        maxSize: maxSize,
        directory: cacheDirectory,
        filesCount: 1,
        opCompactThreshold: 200);

    print('============================\n${cacheDirectory.path}');

    // write stream
    CacheEditor editor = await cache.edit('imagekey');
    if (editor != null) {
      HttpClient client = new HttpClient();
      HttpClientRequest request = await client.openUrl(
          "GET",
          Uri.parse(
              "https://ss0.bdstatic.com/94oJfD_bAAcT8t7mm9GUKT-xh_/timg?image&quality=100&size=b4000_4000&sec=1534075481&di=1a90bd266d62bc5edfe1ce84ac38330e&src=http://photocdn.sohu.com/20130517/Img376200804.jpg"));
      HttpClientResponse response = await request.close();
      Stream<List<int>> stream = await editor.copyStream(0, response);
      // The bytes has been written to disk at this point.
      await new ByteStream(stream).toBytes();
      await editor.commit();

      // read stream
      CacheSnapshot snapshot = await cache.get('imagekey');
      Uint8List bytes = await snapshot.getBytes(0);
      print(bytes.length);
    }
  });

  test("Basic usage width string", () async {
    DiskLruCache cache = new DiskLruCache(
        maxSize: maxSize,
        directory: cacheDirectory,
        filesCount: 1,
        opCompactThreshold: 200);

    // write stream
    CacheEditor editor = await cache.edit('filekey');
    if (editor != null) {
      IOSink sink = await editor.newSink(0);
      sink.write('your value');
      await sink.close();
      await editor.commit();
    }

    // read stream
    CacheSnapshot snapshot = await cache.get('filekey');
    String str = await snapshot.getString(0);
    print(str);
  });

  Future testCache() async {
    DiskLruCache cache = new DiskLruCache(
        maxSize: maxSize,
        directory: cacheDirectory,
        filesCount: 1,
        opCompactThreshold: 200);
    print(cache.directory);

    String str200k;
    String get200k() {
      if (str200k == null) {
        StringBuffer sb = new StringBuffer();

        for (int i = 0, c = 200 * 1024; i < c; ++i) {
          sb.write("a");
        }

        str200k = sb.toString();
      }
      return str200k;
    }

    Future test() async {
      // we must wait the file created
      List<Future> list = [];
      List<Future> writeDisk = [];
      List<Future> openWrite = [];

      void editValue(DiskLruCache cache, String key, String value) {
        list.add(cache.edit(key).then((CacheEditor editor) {
          if (editor != null) {
            openWrite.add(editor.newSink(0).then((IOSink sink) async {
              writeDisk.add((() async {
                if (sink != null) {
                  sink.write(value);
                  await sink.close();

                  await editor.commit();
                } else {
                  print("Sink is null");
                }
              })());
            }).catchError((e) {
              print(e);
            }));
          } else {
            print("Cannot open editor for key $key");
          }
        }));
      }

      Future useCache(DiskLruCache cache) async {
        int random() {
          // 200k * 100 = 20M
          return new Math.Random().nextInt(100);
        }

        //we open 10 files at the same time
        for (int i = 0; i < 10; ++i) {
          editValue(cache, "${random()}", get200k());
          String key = "${random()}";
          cache.get(key).then((CacheSnapshot s) {
            if (s == null) {
              print('Cache miss $key');
              return;
            }
            s.getString(0).then((String str) {
              print("Cache hit $key");
            });
          });
          //cache.remove("${random()}");
        }
      }

      await useCache(cache);

      await Future.wait(list);
      await Future.wait(openWrite);
      await Future.wait(writeDisk);
    }

    // our operation times must > 2000,so that we can test rebuild record file.
    for (int i = 0; i < 10; ++i) {
      await test();
    }

    int size = cache.size;

    Iterable<CacheEntry> entries = await cache.values;
    int calcSize = 0;
    entries.forEach((CacheEntry entry) {
      calcSize += entry.size;
    });

    expect(cache.size, calcSize);

    expect(cache.size < maxSize, true);

    await cache.close();
    print("Cache size : ${cache.size/1024/1024} m ");
  }

  Future testRemoveAll() async {
    DiskLruCache cache = new DiskLruCache(
        maxSize: maxSize, directory: cacheDirectory, filesCount: 1);
    List<bool> results = await cache.clean();
    expect(results.every((bool value) => value), true);
    expect(cache.size, 0);
  }

  test('Lru cache', () async {
    await (() async {
      await testCache();
    })();

    // do it again
    await (() async {
      await testCache();
    })();

    //test remove
    await (() async {
      await testRemoveAll();
    })();
  });

  test("Test commit errors", () async {
    DiskLruCache cache = new DiskLruCache(
        maxSize: maxSize, directory: cacheDirectory, filesCount: 2);
    // write stream
    CacheEditor editor = await cache.edit('filekey');
    if (editor != null) {
      IOSink sink = await editor.newSink(0);
      sink.write('your value');
      await sink.close();
      await editor.commit();

      CacheSnapshot snapshot = await cache.get("filekey");
      expect(snapshot, null);
    }
  });

  test("Simulate errors when write to disk", () async {
    DiskLruCache cache = new DiskLruCache(
        maxSize: maxSize, directory: cacheDirectory, filesCount: 1);
    // write stream
    CacheEditor editor = await cache.edit('errorkey');
    if (editor != null) {
      IOSink sink = await editor.newSink(0);

      CacheSnapshot snapshot;

      sink.write('your value');
      await sink.flush();

      //remove the file
      Iterable<CacheEntry> values = await cache.values;
      values = values.where((CacheEntry entry) {
        return entry.key == "errorkey";
      });
      await values.toList()[0].dirtyFiles[0].delete();

      await sink.close();
      await editor.commit();

      expect(await cache.get("errorkey"), null);
    }
  });

  test("Simulate errors when read from disk", () {});
}
