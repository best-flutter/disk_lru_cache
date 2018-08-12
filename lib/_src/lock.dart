import 'dart:async';

class SynchronizedLock {
  static Map<Function, Future> _map = new Map();

  /// Execute a asynchronous function once at the same time
  static Future execute(Function func,
      [List positionedArguments, Map<Symbol, dynamic> namedArguments]) {
    Future future = _map[func];
    if (future != null) {
      return future;
    }
    var result =
        Function.apply(func, positionedArguments ?? [], namedArguments);
    assert(result is Future, "The function must return a Future");
    future = result.whenComplete(() {
      _map.remove(func);
    });
    _map[func] = future;
    return future;
  }

  static bool debug = false;

  static Map<Object, List<_PoolItem>> _executePool = new Map();

  /// Make all function call sequence on one `lock`,
  /// Re-entrant lock in dart
  static Future<T> synchronized<T>(Object lock, Function call) {
    Zone current = Zone.current;
    Set _lock = current['lock'];
    if (current == Zone.root || _lock == null || !_lock.contains(lock)) {
      if (debug) print("Add to queue $call");
      if (_lock == null) {
        _lock = new Set();
      }
      _lock.add(lock);

      return Zone.root.fork(zoneValues: {"lock": _lock}).run<Future<T>>(() {
        if (debug) print("========================${Zone.current.hashCode}");

        List<_PoolItem> value = _executePool[lock];
        var next = () {
          if (debug) print("next!");
          if (value.length <= 0) {
            return;
          }
          _PoolItem item = value.removeAt(0);
          Future future = item.execute();
          future.whenComplete(() {
            if (debug)
              print(
                  "Complete a function in Zone : ${item.zone.hashCode} remove lock: $lock");

            Set locks = item.zone['lock'];
            if (locks != null) {
              locks.remove(lock);
            }

            if (value.length <= 0) {
              _executePool.remove(lock);
            }
          });
        };
        _PoolItem<T> item = new _PoolItem<T>(call, next, current);
        if (value == null) {
          value = [item];
          _executePool[lock] = value;
          next();
        } else {
          value.add(item);
        }

        return item.done;
      });
    } else {
      if (debug) print("Execute directly");
      return new _PoolItem(call, () {
        if (debug) print("next directy");
      }, current)
          .execute();
    }
  }
}

class _PoolItem<T> {
  Completer<T> _completer = new Completer();
  Zone zone;
  Function call;
  Function next;

  _PoolItem(this.call, this.next, this.zone);

  Future execute() {
    var future;
    try {
      future = call();
      if (future is Future || future is Future<T>) {
        future
            .then((data) {
              _completer.complete(data);
            })
            .catchError(_completer.completeError)
            .whenComplete(next);
        return future;
      } else {
        future = new Future<T>.value(future);
        _completer.complete(future);
        next();
        return future;
      }
    } catch (e) {
      print("Execute error : $e");
      _completer.completeError(e);
      next();
      return new Future.error(e);
    }
  }

  Future get done => _completer.future;
}
