import 'dart:async';
import 'dart:io';

import 'package:disk_lru_cache/_src/disk_lru_cache.dart';
import 'package:test/test.dart';

import 'package:disk_lru_cache/disk_lru_cache.dart';

void main() {
  Object a = new Object();
  Object b = new Object();

  List<String> sequence = [];

  Future executeLocks(a, b) {
    return SynchronizedLock.synchronized(a, () async {
      print("Sync a start");
      sequence.add("AStart");

      assert(Zone.current['lock'] != null);
      assert(Zone.current['lock'] is Set);
      Set set = Zone.current['lock'];
      print("${Zone.current.hashCode} $set");

      assert(set.contains(a));

      await SynchronizedLock.synchronized(b, () async {
        assert(Zone.current['lock'] != null);
        assert(Zone.current['lock'] is Set);
        assert(Zone.current['lock'].contains(a));
        assert(Zone.current['lock'].contains(b));

        print("Sync b start");

        sequence.add("BStart");

        await SynchronizedLock.synchronized(a, () async {
          print("Sync inner a start");
          sequence.add("InnerAStart");
          assert(Zone.current['lock'] != null);
          assert(Zone.current['lock'] is Set);
          assert(Zone.current['lock'].contains(a));
          assert(Zone.current['lock'].contains(b));

          await new Future.delayed(new Duration(milliseconds: 100));
          sequence.add("InnerAEnd");
          print("Sync inner a end");
        });
        sequence.add("BEnd");
        print("Sync b end");
      });
      sequence.add("AEnd");
      print("Sync a end==============");
    });
  }

  Future testLock() async {
    Object a = "lock1";
    Object b = "lock2";
    executeLocks(a, b);
    executeLocks(a, b);
    return executeLocks(a, b);
  }

  test('Test lock by await', () async {
    await testLock();

    expect(
        sequence,
        []
          ..addAll(
              ["AStart", "BStart", "InnerAStart", "InnerAEnd", "BEnd", "AEnd"])
          ..addAll(
              ["AStart", "BStart", "InnerAStart", "InnerAEnd", "BEnd", "AEnd"])
          ..addAll([
            "AStart",
            "BStart",
            "InnerAStart",
            "InnerAEnd",
            "BEnd",
            "AEnd"
          ]));
  });
}
