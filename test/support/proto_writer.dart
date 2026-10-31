import 'dart:convert';
import 'dart:typed_data';

/// Tiny protobuf encoder used to build tombstones in tests.
class ProtoWriter {
  final _out = BytesBuilder();

  void _varint(int value) {
    var v = value;
    for (var i = 0; i < 10; i++) {
      final byte = v & 0x7f;
      v = v >>> 7;
      if (v == 0) {
        _out.addByte(byte);
        return;
      }
      _out.addByte(byte | 0x80);
    }
  }

  void _key(int field, int wire) => _varint(field << 3 | wire);

  ProtoWriter varint(int field, int value) {
    _key(field, 0);
    _varint(value);
    return this;
  }

  ProtoWriter bytes(int field, List<int> value) {
    _key(field, 2);
    _varint(value.length);
    _out.add(value);
    return this;
  }

  ProtoWriter string(int field, String value) =>
      bytes(field, utf8.encode(value));

  ProtoWriter message(int field, ProtoWriter value) =>
      bytes(field, value.toBytes());

  ProtoWriter fixed64(int field) {
    _key(field, 1);
    _out.add(List.filled(8, 0xAB));
    return this;
  }

  ProtoWriter fixed32(int field) {
    _key(field, 5);
    _out.add(List.filled(4, 0xCD));
    return this;
  }

  Uint8List toBytes() => _out.toBytes();
}
