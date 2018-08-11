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

  static Map<Object, List<_PoolItem>> _executePool = new Map();

  /// Make all function call sequence on one `lock`
  static Future<T> synchronized<T>(Object lock, Function call) {
    Zone current = Zone.current;
    Object _lock = current['lock'];
    if (current == Zone.root || _lock != lock) {
      return Zone.root.fork(
          zoneValues: {"lock": lock},
          specification: new ZoneSpecification(handleUncaughtError: (Zone self,
              ZoneDelegate parent,
              Zone zone,
              Object error,
              StackTrace stackTrace) {
            print(stackTrace);
          })).run<Future<T>>(() {
        List<_PoolItem> value = _executePool[lock];
        var next = () {
          if(value.length <= 0){
            return;
          }
          _PoolItem item = value.removeAt(0);
          Future future = item.execute();
          future.whenComplete((){
            if(value.length<=0){
              _executePool.remove(lock);
            }
          });
        };
        _PoolItem<T> item = new _PoolItem<T>(call, next);
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
      return call();
    }
  }
}

class _PoolItem<T> {
  Completer<T> _completer = new Completer();

  Function call;
  Function next;

  _PoolItem(this.call, this.next);

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
