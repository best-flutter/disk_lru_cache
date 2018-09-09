
<p align="center">
    <a href="https://travis-ci.org/best-flutter/disk_lru_cache">
        <img src="https://travis-ci.org/best-flutter/disk_lru_cache.svg?branch=master" alt="Build Status" />
    </a>
    <a href="https://coveralls.io/github/best-flutter/disk_lru_cache?branch=master">
        <img src="https://coveralls.io/repos/github/best-flutter/disk_lru_cache/badge.svg?branch=master" alt="Coverage Status" />
    </a>
    <a href="https://github.com/best-flutter/disk_lru_cache/pulls">
        <img src="https://img.shields.io/badge/PRs-Welcome-brightgreen.svg" alt="PRs Welcome" />
    </a>
    <a href="https://pub.dartlang.org/packages/disk_lru_cache">
        <img src="https://img.shields.io/pub/v/disk_lru_cache.svg" alt="pub package" />
    </a>
</p>



# disk_lru_cache
Disk lru cache for flutter. [wiki](https://en.wikipedia.org/wiki/Cache_replacement_policies#Least_recently_used_(LRU))

A cache that uses a bounded amount of space on a filesystem. 
Each cache entry has a string key and a fixed number of files, witch is accessible as stream.

# Use cases


## Working with memery

We provided a `LruMap` ,in order to support LRU order in memory, witch is a subclass of Map.So ,wo can use the `LruMap` just like Map



```
final LruMap<String, int> map = new LruMap();

expect(map.values.toList().length, 0);

map['a'] = 1;
map['b'] = 2;
map['c'] = 3;

/// use the key 'a'
var f = map['a'];

/// We use the key 'a', so at this moment it is the last element.
alues = map.values;
expect(values.toList()[0], 2);
expect(values.toList()[1], 3);
expect(values.toList()[2], 1);

```


## Working with file system

The basic usage is like this:


With string:

```
int maxSize =
      10 * 1024 * 1024; // 10M

// Make sure it's writable
Directory cacheDirectory =
            new Directory("${Directory.systemTemp.path}/cache");

 DiskLruCache cache = new DiskLruCache(
        maxSize: maxSize, directory: cacheDirectory, filesCount: 1);

    // write stream
    CacheEditor editor = await cache.edit('filekey');
    if(editor!=null){
      IOSink sink = await editor.newSink(0);
      sink.write('your value');
      await sink.close();
      await editor.commit();
    }

    // read stream
    CacheSnapshot snapshot =  await cache.get('filekey');
    String str = await snapshot.getString(0);
    print(str);

```


With bytes

```
// write bytes
  CacheEditor editor = await cache.edit('imagekey');
  if(editor!=null){
    HttpClient client = new HttpClient();
    HttpClientRequest request = await client.openUrl("GET", Uri.parse("https://ss0.bdstatic.com/94oJfD_bAAcT8t7mm9GUKT-xh_/timg?image&quality=100&size=b4000_4000&sec=1534075481&di=1a90bd266d62bc5edfe1ce84ac38330e&src=http://photocdn.sohu.com/20130517/Img376200804.jpg"));
    HttpClientResponse response = await request.close();
    Stream<List<int>> stream = await editor.copyStream(0, response);
    // The bytes has been written to disk at this point.
    await new ByteStream(stream).toBytes();
    await editor.commit();

    // read stream
    CacheSnapshot snapshot =  await cache.get('imagekey');
    Uint8List bytes = await snapshot.getBytes(0);
    print(bytes);
  }

```




