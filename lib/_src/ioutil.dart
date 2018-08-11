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

class IOSinkProxy implements IOSink {
  final IOSink sink;
  final IOSinkOnError onError;

  IOSinkProxy(this.sink,{this.onError})
      : assert(onError!=null), encoding = sink.encoding;

  @override
  Encoding encoding;

  @override
  void add(List<int> data) {
    try{
      sink.add(data);
    }catch(e){
      this.onError(e);
    }
  }

  @override
  void addError(Object error, [StackTrace stackTrace]) {
    sink.addError(error, stackTrace);
  }

  @override
  Future addStream(Stream<List<int>> stream) {
    return sink.addStream(stream);
  }

  @override
  Future close() {
    return sink.close();
  }

  @override
  Future get done => sink.done;

  @override
  Future flush() {
    return sink.flush();
  }

  @override
  void write(Object obj) {
    try{
      sink.write(obj);
    }catch(e){
      this.onError(e);
    }

  }

  @override
  void writeAll(Iterable objects, [String separator = ""]) {
    sink.writeAll(objects, separator);
  }

  @override
  void writeCharCode(int charCode) {
    sink.writeCharCode(charCode);
  }

  @override
  void writeln([Object obj = ""]) {
    sink.writeln(obj);
  }
}
