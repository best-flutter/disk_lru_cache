import 'dart:async';
import 'dart:convert';

import 'dart:io';


///
/// When a Stream is receiving events, this class also receiving the same events.
///
class CloseableStream<T> extends Stream<T> implements Closeable {
  StreamSubscription<T> _streamSubscription;

  final Stream<T> _stream;
  final void Function(T event) onData;
  final void Function() onDone;
  final Function onError;

  CloseableStream(
      this._stream, {
        this.onData,
        this.onDone,
        this.onError,
      });

  @override
  StreamSubscription<T> listen(void Function(T event) onData,
      {Function onError, void Function() onDone, bool cancelOnError}) {
    assert(onData != null);
    void Function(T event) _onData;
    if (this.onData != null && onData != null) {
      _onData = (T event) {
        this.onData(event);
        onData(event);
      };
    } else {
      _onData = onData ?? this.onData;
    }

    Function _onError;
    if (this.onError != null && onError != null) {
      _onError = (e) {
        this.onError(e);
        onError(e);
      };
    } else {
      _onError = onError ?? this.onError;
    }

    void Function() _onDone;
    if (this.onDone != null && onDone != null) {
      _onDone = () {
        this.onDone();
        onDone();
      };
    } else {
      _onDone = onDone ?? this.onDone;
    }

    try {
      _streamSubscription = _stream.listen(_onData,
          onError: _onError, onDone: _onDone, cancelOnError: cancelOnError);
      return _streamSubscription;
    } catch (e) {
      _onError(e);
      rethrow;
    }
  }

  @override
  Future close() {
    if (_streamSubscription == null) {
      return new Future.value();
    }
    return _streamSubscription.cancel();
  }
}

class IoUtil{

  static Future<String> stream2String(CloseableStream<List<int>> stream,Encoding encoding){
    Completer<String> completer = new Completer();
    StringBuffer stringBuffer = new StringBuffer();
    stream.transform(encoding.decoder).listen((String content) {
      stringBuffer.write(content);
    }, onDone: () {
      stream.close();
      completer.complete(stringBuffer.toString());
    }, onError: (e) {
      stream.close();
      completer.completeError(e);
    }, cancelOnError: true);

    return completer.future;
  }
}

abstract class Closeable {
  Future close();
}

/// This IOSink do nothing when operation
class EmptyIOSink implements IOSink {
  @override
  Encoding encoding;

  @override
  void add(List<int> data) {}

  @override
  void addError(Object error, [StackTrace stackTrace]) {}

  @override
  Future addStream(Stream<List<int>> stream) {
    return new Future.value();
  }

  @override
  Future close() {
    return new Future.value();
  }

  @override
  Future get done => new Future.value();

  @override
  Future flush() {
    return new Future.value();
  }

  @override
  void write(Object obj) {}

  @override
  void writeAll(Iterable objects, [String separator = ""]) {}

  @override
  void writeCharCode(int charCode) {}

  @override
  void writeln([Object obj = ""]) {}
}

typedef void IOSinkOnError(e);

/// This IOSink do not throw errors
class IOSinkProxy implements IOSink {
  final IOSink sink;
  final IOSinkOnError onError;

  IOSinkProxy(this.sink, {this.onError})
      : assert(onError != null),
        encoding = sink.encoding;

  @override
  Encoding encoding;

  @override
  void add(List<int> data) {
    try {
      sink.add(data);
    } catch (e) {
      this.onError(e);
    }
  }

  @override
  void addError(Object error, [StackTrace stackTrace]) {
    sink.addError(error, stackTrace);
  }

  @override
  Future addStream(Stream<List<int>> stream) async {
    try {
      return await sink.addStream(stream);
    } catch (e) {
      this.onError(e);
    }
  }

  @override
  Future close() async {
    try {
      return await sink.close();
    } catch (e) {
      this.onError(e);
    }
  }

  @override
  Future get done => sink.done;

  @override
  Future flush() async {
    try {
      return await sink.flush();
    } catch (e) {
      this.onError(e);
    }
  }

  @override
  void write(Object obj) {
    try {
      sink.write(obj);
    } catch (e) {
      this.onError(e);
    }
  }

  @override
  void writeAll(Iterable objects, [String separator = ""]) {
    try {
      sink.writeAll(objects, separator);
    } catch (e) {
      this.onError(e);
    }
  }

  @override
  void writeCharCode(int charCode) {
    try {
      sink.writeCharCode(charCode);
    } catch (e) {
      this.onError(e);
    }
  }

  @override
  void writeln([Object obj = ""]) {
    try {
      sink.writeln(obj);
    } catch (e) {
      this.onError(e);
    }
  }
}
