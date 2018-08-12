import 'dart:async';
import 'dart:convert';

import 'dart:io';

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
