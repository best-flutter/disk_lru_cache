import 'dart:async';
import 'dart:io';

import 'package:disk_lru_cache/_src/disk_lru_cache.dart';
import 'package:test/test.dart';
import 'dart:math' as Math;
import 'package:disk_lru_cache/disk_lru_cache.dart';
void main() {

  Future testCache() async {

    int maxSize = 10 * 1024 * 1024; // 10M,make sure to test rebuild progress below
    DiskLruCache cache = new DiskLruCache(
        maxSize:maxSize ,
        directory: new Directory("${Directory.systemTemp.path}/cache"),
        filesCount: 1);
    print(cache.directory);

    String str200k ;
    String get200k(){
      if(str200k==null){
        StringBuffer sb = new StringBuffer();

        for(int i=0 , c = 200 * 1024; i < c; ++i){
          sb.write("a");
        }

        str200k= sb.toString();
      }
      return str200k;


    }

    Future test() async{


      // we must wait the file created
      List<Future> list = [];
      List<Future> writeDisk = [];
      List<Future> openWrite=[];

      void editValue(DiskLruCache cache, String key, String value) {
        list.add(cache.edit(key).then( (CacheEditor editor){
          if (editor != null) {
            openWrite.add(editor.newSink(0).then((IOSink sink) async {

              writeDisk.add( ( () async{
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
          }else{
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
    for(int i=0; i < 10; ++i){
      await test();
    }

    await cache.close();

    print("Cache size : ${cache.size/1024/1024} m ");

    assert( cache.size < maxSize);
  }


  test('Lru cache', () async {
    await (() async {
     await testCache();
    })();
  });
}
