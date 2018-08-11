import 'dart:io';

import 'package:disk_lru_cache/_src/disk_lru_cache.dart';
import 'package:test/test.dart';

import 'package:disk_lru_cache/disk_lru_cache.dart';

void main() {
  test('Lru cache', () {
    DiskLruCache cache = new DiskLruCache(directory: Directory.systemTemp);
    cache.get("123");
  });
}
