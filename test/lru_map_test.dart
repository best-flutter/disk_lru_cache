import 'dart:io';

import 'package:disk_lru_cache/_src/disk_lru_cache.dart';
import 'package:test/test.dart';

import 'package:disk_lru_cache/disk_lru_cache.dart';

void main() {
  test('Lru map', () {
    final LruMap<String, int> map = new LruMap();

    expect(map.values.toList().length, 0);

    map['a'] = 1;
    map['b'] = 2;
    map['c'] = 3;

    Iterable<int> values = map.values;
    print(values);

    expect(values.toList()[0], 1);
    expect(values.toList()[1], 2);
    expect(values.toList()[2], 3);

    /// use the key 'a'
    var f = map['a'];

    expect(f, 1);

    values = map.values;
    print(values);
    expect(values.length, 3);
    expect(values.length, map.length);
    expect(values.toList()[0], 2);
    expect(values.toList()[1], 3);
    expect(values.toList()[2], 1);

    Iterable<String> keys = map.keys;

    expect(keys.toList()[0], 'b');
    expect(keys.toList()[1], 'c');
    expect(keys.toList()[2], 'a');
    expect(map.isEmpty, false);
    expect(map.isNotEmpty, true);

    int value = map.removeHead();
    expect(value, 2);
    keys = map.keys;
    expect(keys.length, 2);
    expect(keys.length, map.length);
    expect(keys.toList()[0], 'c');
    expect(keys.toList()[1], 'a');

    map.remove('a');
    keys = map.keys;
    expect(keys.length, 1);
    expect(keys.length, map.length);
    expect(keys.toList()[0], 'c');

    bool excuted = false;
    //other operation
    map.putIfAbsent("d", () {
      excuted = true;
      return 4;
    });

    keys = map.keys;
    expect(keys.length, 2);
    expect(keys.length, map.length);
    expect(keys.toList()[0], 'c');
    expect(keys.toList()[1], 'd');
    expect(excuted, true);

    excuted = false;
    map.putIfAbsent("c", () {
      excuted = true;
      return 5;
    });
    expect(excuted, false);
    keys = map.keys;
    expect(keys.length, 2);
    expect(keys.length, map.length);
    expect(keys.toList()[0], 'c');
    expect(keys.toList()[1], 'd');

    map.update("c", (int value) {
      return 4;
    }, ifAbsent: () {
      return 0;
    });

    expect(map['c'], 4);

    map.update("e", (int value) {
      return 8;
    }, ifAbsent: () {
      return 0;
    });

    expect(map['e'], 0);

    map.updateAll((String key, int value) {
      return value + 1;
    });

    expect(map['e'], 1);

    Map<int, int> casted = map.cast<int, int>();

    expect(casted != null, true);

    int now = new DateTime.now().millisecondsSinceEpoch;
    for (int i = 0; i < 10000; ++i) {
      map['key$i'] = i;
    }

    print(new DateTime.now().millisecondsSinceEpoch - now);

    now = new DateTime.now().millisecondsSinceEpoch;
    Map org = {};
    for (int i = 0; i < 10000; ++i) {
      org['key$i'] = i;
    }

    print(new DateTime.now().millisecondsSinceEpoch - now);
  });

  test("test map ", () {
    LruMap map = LruMap.of({"a": "1", "b": "2", "c": "3"});

    expect(map.removeHead(), "1");
    expect(map.removeHead(), "2");
    expect(map.removeHead(), "3");
    expect(map.removeHead(), null);
  });

  test("test clear ", () {
    LruMap map = LruMap.of({"a": "1", "b": "2", "c": "3"});

    expect(map.length, 3);

    map.clear();

    expect(map.length, 0);
  });

  test("Lru map other", () {
    LruMap map = LruMap.of({"a": "1", "b": "2", "c": "3"});

    LruMap other = new LruMap();
    other.addEntries(map.entries);

    print(other.values);

    expect(other.values.toList()[0], "1");
    expect(other.values.toList()[1], "2");
    expect(other.values.toList()[2], "3");
    expect(other.containsKey('a'), true);

    other.forEach((key, value) {
      print(value);
    });

    expect(other.containsValue("1"), true);

    other.removeWhere((key, value) {
      return key == "a";
    });

    expect(other['a'], null);

    expect(other.containsKey('a'), false);
    expect(other.containsValue('1'), false);
  });
}
