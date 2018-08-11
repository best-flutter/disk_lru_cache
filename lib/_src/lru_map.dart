import 'dart:core';

///
/// A collection of key/value pairs,
/// The order of the items in this class dependents on how `recent` we use the key,
/// the more recent we use the key , the order is bigger.
///
/// Witch means the head of the LRU list is the lest recent visited,
/// and will be more likely to be removed in future
///
/// For example:
///   LruMap map = new LruMap();
///   map['a']=1;
///   map['b']=2;
///   map['c']=3;
///   print(map.values); -> 1,2,3
///
///   var f = map['a'];  // this action will take key:a to the tail of the LRU list
///   print(map.values); -> 2,3,1
///
///
class LruMap<K, V> implements Map<K, V> {
  _Entry<K, V> head;
  _Entry<K, V> tail;

  final Map<K, _Entry<K, V>> _inner = new Map();

  int get length => _inner.length;

  Iterable<V> get values {
    List<V> list = [];
    for (_Entry<K, V> e = head; e != null; e = e.after) {
      list.add(e.value);
    }
    return list;
  }

  Iterable<K> get keys {
    List<K> list = [];
    for (_Entry<K, V> e = head; e != null; e = e.after) {
      list.add(e.key);
    }
    return list;
  }

  void clear() {
    _inner.clear();
    head = tail = null;
  }

  @override
  V operator [](Object key) {
    //
    _Entry<K, V> node = _inner[key];
    if (node == null) return null;
    _afterNodeAccess(node);
    return node.value;
  }

  void _afterNodeRemoval(_Entry<K, V> e) {
    // unlink
    _Entry<K, V> p = e, b = p.before, a = p.after;
    p.before = p.after = null;
    if (b == null)
      head = a;
    else
      b.after = a;
    if (a == null)
      tail = b;
    else
      a.before = b;
  }

  V remove(Object key) {
    _Entry<K, V> node = _inner.remove(key);
    if (node == null) return null;
    _afterNodeRemoval(node);
    return node.value;
  }

  void _linkNodeLast(_Entry<K, V> p) {
    _Entry<K, V> last = tail;
    tail = p;
    if (last == null)
      head = p;
    else {
      p.before = last;
      last.after = p;
    }
  }

  V removeHead() {
    _Entry<K, V> head = this.head;
    if (head == null) {
      return null;
    }
    if (head == tail) {
      //just one
      head.before = head.after = null;
      this.head = this.tail = null;
    } else {
      this.head = head.after;
      this.head.before = null;
      head.after = null;
    }

    _inner.remove(head.key);

    return head.value;
  }

  // move to end of the list
  void _afterNodeAccess(_Entry<K, V> e) {
    _Entry<K, V> last;
    if ((last = tail) != e) {
      _Entry<K, V> p = e, b = p.before, a = p.after;
      p.after = null;
      if (b == null)
        head = a;
      else
        b.after = a;
      if (a != null)
        a.before = b;
      else
        last = b;
      if (last == null)
        head = p;
      else {
        p.before = last;
        last.after = p;
      }
      tail = p;
    }
  }

  @override
  void addAll(Map<K, V> other) {
    assert(other != null);
    other.forEach((K key, V value) {
      this[key] = value;
    });
  }

  @override
  void addEntries(Iterable<MapEntry<K, V>> newEntries) {
    newEntries.map((MapEntry<K, V> entry) {
      this[entry.key] = entry.value;
    });
  }

  @override
  bool containsKey(Object key) {
    return _inner.containsKey(key);
  }

  @override
  bool containsValue(Object value) {
    return _inner.containsValue(value);
  }

  @override
  bool get isEmpty => _inner.isEmpty;

  @override
  bool get isNotEmpty => _inner.isNotEmpty;
  @override
  void forEach(void Function(K key, V value) f) {
    for (_Entry<K, V> e = head; e != null; e = e.after) {
      f(e.key, e.value);
    }
  }

  @override
  void removeWhere(bool Function(K key, V value) predicate) {
    _inner.removeWhere((K _key, _Entry<K, V> _value) {
      if (predicate(_key, _value.value)) {
        _afterNodeRemoval(_value);
        return true;
      }
      return false;
    });
  }

  @override
  Iterable<MapEntry<K, V>> get entries {
    List<MapEntry<K, V>> list = [];
    for (_Entry<K, V> e = head; e != null; e = e.after) {
      list.add(new MapEntry(e.key, e.value));
    }
    return list;
  }

  _Entry _createNew(K key, V value) {
    _Entry<K, V> entry = new _Entry(key: key, value: value);
    _linkNodeLast(entry);
    return entry;
  }

  void operator []=(K key, dynamic value) {
    _Entry<K, V> node = _inner[key];
    if (node == null) {
      _inner[key] = _createNew(key, value);
    } else {
      //new Node
      _afterNodeAccess(node);
    }
  }

  @override
  V putIfAbsent(K key, V Function() ifAbsent) {
    assert(ifAbsent != null);
    return _inner.putIfAbsent(key, () {
      V value = ifAbsent();
      return _createNew(key, value);
    })?.value;
  }

  @override
  V update(K key, V Function(V value) update, {V Function() ifAbsent}) {
    assert(update != null);
    var updateFunc = (_Entry<K, V> _value) {
      V value = update(_value.value);
      _value.value = value;
      _afterNodeAccess(_value);
      return _value;
    };
    if (ifAbsent != null) {
      return _inner.update(key, updateFunc, ifAbsent: () {
        V value = ifAbsent();
        return _createNew(key, value);
      })?.value;
    } else {
      return _inner.update(key, updateFunc)?.value;
    }
  }

  @override
  void updateAll(V Function(K key, V value) update) {
    assert(update != null);
    _inner.updateAll((K _key, _Entry<K, V> _value) {
      V value = update(_key, _value.value);
      _value.value = value;

      /// update all values,we need to update all element orders,
      /// witch is not necessary here.

      return _value;
    });
  }

  @deprecated
  @override
  Map<RK, RV> retype<RK, RV>() {
    return _inner.retype<RK, RV>();
  }

  @override
  Map<RK, RV> cast<RK, RV>() {
    return _inner.cast<RK, RV>();
  }

  @override
  Map<K2, V2> map<K2, V2>(MapEntry<K2, V2> Function(K key, V value) f) {
    throw new Exception("No implement");
  }
}

/// Store key and value
class _Entry<K, V> {
  final K key;
  V value;

  _Entry<K, V> before;
  _Entry<K, V> after;

  _Entry({this.key, this.value});
}
