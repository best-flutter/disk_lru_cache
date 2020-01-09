import 'dart:async';
import 'dart:io';
import 'dart:math' as Math;
import 'dart:typed_data';

import 'package:disk_lru_cache/_src/disk_lru_cache.dart';
import 'package:disk_lru_cache/disk_lru_cache.dart';
import 'package:http/http.dart';

Future testCache() async {
  int maxSize =
      10 * 1024 * 1024; // 10M,make sure to test rebuild progress below
  DiskLruCache cache = new DiskLruCache(
      maxSize: maxSize,
      directory: new Directory("${Directory.systemTemp.path}/cache"),
      filesCount: 1,
      opCompactThreshold: 200);
  print(cache.directory);
  CacheEditor editor;
  // write stream
  editor = await cache.edit('errorkey');
  if (editor != null) {
    IOSink sink = await editor.newSink(0);
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
  }

  // write stream
  editor = await cache.edit('imagekey');
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
    print(bytes);
  }

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

      //we open 10 files a time
      for (int i = 0; i < 10; ++i) {
        editValue(cache, "${random()}", get200k());
        String key = "${random()}";
        cache.get(key).then((CacheSnapshot s) {
          if (s == null) {
            print('Cache miss $key');
            return;
          }
          s.getString(0).then((String str) {
            print("Cache hit $key=$str");
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

  Iterable<CacheEntry> entries = await cache.values;

  List<Future<bool>> list = [];
  for (CacheEntry entry in entries) {
    list.add(cache.remove(entry.key));
  }
  await Future.wait(list);

  assert(cache.size == 0);

  await cache.close();

  print("Cache size : ${cache.size / 1024 / 1024} m ");

  assert(cache.size < maxSize);
}
