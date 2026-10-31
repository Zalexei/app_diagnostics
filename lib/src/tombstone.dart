import 'dart:convert';
import 'dart:typed_data';

/// CPU architecture of a tombstone (`Architecture` in tombstone.proto).
enum TombstoneArch {
  arm32('arm'),
  arm64('arm64'),
  x86('x86'),
  x86_64('x86_64'),
  riscv64('riscv64'),
  none('none'),
  unknown('unknown');

  const TombstoneArch(this.abi);

  /// The name debuggerd prints after `ABI:`.
  final String abi;

  static TombstoneArch fromCode(int code) =>
      code >= 0 && code < unknown.index ? values[code] : unknown;
}

/// The fatal signal (`Signal` in tombstone.proto).
class TombstoneSignal {
  const TombstoneSignal({
    required this.number,
    required this.name,
    required this.code,
    required this.codeName,
    required this.hasSender,
    required this.senderUid,
    required this.senderPid,
    required this.hasFaultAddress,
    required this.faultAddress,
  });

  final int number;

  /// e.g. `SIGSEGV`, `SIGABRT`.
  final String name;
  final int code;

  /// e.g. `SEGV_MAPERR`, `SI_TKILL`.
  final String codeName;
  final bool hasSender;
  final int senderUid;
  final int senderPid;
  final bool hasFaultAddress;
  final int faultAddress;
}

/// One stack frame (`BacktraceFrame` in tombstone.proto).
class TombstoneFrame {
  const TombstoneFrame({
    required this.relPc,
    required this.pc,
    required this.sp,
    required this.functionName,
    required this.functionOffset,
    required this.fileName,
    required this.fileMapOffset,
    required this.buildId,
  });

  /// PC relative to the start of the mapped file: feed it to `llvm-symbolizer`
  /// or `ndk-stack` together with [buildId].
  final int relPc;
  final int pc;
  final int sp;
  final String functionName;
  final int functionOffset;
  final String fileName;
  final int fileMapOffset;
  final String buildId;

  /// The frame as debuggerd prints it, without the `#NN` prefix.
  String format() {
    final out = StringBuffer('pc ${hex64(relPc)}  $fileName');
    if (functionName.isNotEmpty) {
      out.write(' ($functionName');
      if (functionOffset != 0) out.write('+$functionOffset');
      out.write(')');
    }
    if (buildId.isNotEmpty) out.write(' (BuildId: $buildId)');
    return out.toString();
  }
}

/// One thread of the crashed process (`Thread` in tombstone.proto).
class TombstoneThread {
  const TombstoneThread({
    required this.id,
    required this.name,
    required this.backtrace,
    required this.backtraceNote,
  });

  final int id;
  final String name;
  final List<TombstoneFrame> backtrace;

  /// Notes from the unwinder, e.g. why the backtrace is incomplete.
  final List<String> backtraceNote;
}

/// A native crash report: the protobuf tombstone that
/// `ApplicationExitInfo.getTraceInputStream()` returns for
/// [ExitReason.crashNative] on Android 12 (API 31) and newer.
///
/// Only the fields useful for crash triage are decoded: build, process,
/// signal, abort message, causes and the backtrace of every thread.
/// Memory maps, registers, logs and open files are skipped; keep the raw
/// bytes if you need them.
/// Schema: https://android.googlesource.com/platform/system/core/+/refs/heads/main/debuggerd/proto/tombstone.proto
class NativeTombstone {
  const NativeTombstone({
    required this.arch,
    required this.buildFingerprint,
    required this.revision,
    required this.timestamp,
    required this.pid,
    required this.tid,
    required this.uid,
    required this.selinuxLabel,
    required this.commandLine,
    required this.processUptime,
    required this.signal,
    required this.abortMessage,
    required this.causes,
    required this.threads,
  });

  /// Decodes a tombstone. Throws [FormatException] on malformed protobuf.
  factory NativeTombstone.parse(List<int> bytes) {
    final reader = _ProtoReader(
      bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
    );
    var arch = 0;
    var buildFingerprint = '';
    var revision = '';
    var timestamp = '';
    var pid = 0;
    var tid = 0;
    var uid = 0;
    var selinuxLabel = '';
    final commandLine = <String>[];
    var processUptime = 0;
    TombstoneSignal? signal;
    var abortMessage = '';
    final causes = <String>[];
    final threads = <int, TombstoneThread>{};

    while (!reader.isDone) {
      final (field, wire) = reader.readTag();
      switch (field) {
        case 1 when wire == _varint:
          arch = reader.readVarint();
        case 2 when wire == _bytes:
          buildFingerprint = reader.readString();
        case 3 when wire == _bytes:
          revision = reader.readString();
        case 4 when wire == _bytes:
          timestamp = reader.readString();
        case 5 when wire == _varint:
          pid = reader.readVarint();
        case 6 when wire == _varint:
          tid = reader.readVarint();
        case 7 when wire == _varint:
          uid = reader.readVarint();
        case 8 when wire == _bytes:
          selinuxLabel = reader.readString();
        case 9 when wire == _bytes:
          commandLine.add(reader.readString());
        case 10 when wire == _bytes:
          signal = _parseSignal(reader.readMessage());
        case 14 when wire == _bytes:
          abortMessage = reader.readString();
        case 15 when wire == _bytes:
          final cause = _parseCause(reader.readMessage());
          if (cause.isNotEmpty) causes.add(cause);
        case 16 when wire == _bytes:
          final thread = _parseThreadEntry(reader.readMessage());
          threads[thread.id] = thread;
        case 20 when wire == _varint:
          processUptime = reader.readVarint();
        default:
          reader.skip(wire);
      }
    }

    return NativeTombstone(
      arch: TombstoneArch.fromCode(arch),
      buildFingerprint: buildFingerprint,
      revision: revision,
      timestamp: timestamp,
      pid: pid,
      tid: tid,
      uid: uid,
      selinuxLabel: selinuxLabel,
      commandLine: List.unmodifiable(commandLine),
      processUptime: Duration(seconds: processUptime),
      signal: signal,
      abortMessage: abortMessage,
      causes: List.unmodifiable(causes),
      threads: Map.unmodifiable(threads),
    );
  }

  final TombstoneArch arch;
  final String buildFingerprint;
  final String revision;

  /// Crash time as debuggerd formats it, e.g. `2026-10-31 12:00:00.123456789+0000`.
  final String timestamp;
  final int pid;

  /// The thread that crashed.
  final int tid;
  final int uid;
  final String selinuxLabel;
  final List<String> commandLine;
  final Duration processUptime;
  final TombstoneSignal? signal;

  /// Message passed to `abort()` helpers such as `__android_log_assert`.
  final String abortMessage;

  /// Human readable causes found by debuggerd (e.g. use-after-free).
  final List<String> causes;

  /// All threads by thread id.
  final Map<int, TombstoneThread> threads;

  /// The thread that received the fatal signal.
  TombstoneThread? get crashingThread => threads[tid];

  /// A text report in the familiar logcat/debuggerd layout.
  String toText() {
    final out = StringBuffer();
    if (buildFingerprint.isNotEmpty) {
      out.writeln("Build fingerprint: '$buildFingerprint'");
    }
    out.writeln("ABI: '${arch.abi}'");
    if (timestamp.isNotEmpty) out.writeln('Timestamp: $timestamp');
    out.writeln('Process uptime: ${processUptime.inSeconds}s');
    if (commandLine.isNotEmpty) {
      out.writeln('Cmdline: ${commandLine.join(' ')}');
    }
    final crashing = crashingThread;
    final process = commandLine.isEmpty ? '?' : commandLine.first;
    out.writeln(
      'pid: $pid, tid: $tid, name: ${crashing?.name ?? '?'}  >>> $process <<<',
    );
    out.writeln('uid: $uid');
    final sig = signal;
    if (sig != null) {
      final fault = sig.hasFaultAddress
          ? '0x${hex64(sig.faultAddress)}'
          : '--------';
      out.write(
        'signal ${sig.number} (${sig.name}), code ${sig.code} (${sig.codeName}',
      );
      if (sig.hasSender) {
        out.write(' from pid ${sig.senderPid}, uid ${sig.senderUid}');
      }
      out.writeln('), fault addr $fault');
    }
    if (abortMessage.isNotEmpty) out.writeln("Abort message: '$abortMessage'");
    for (final cause in causes) {
      out.writeln('Cause: $cause');
    }
    if (crashing != null) {
      for (final note in crashing.backtraceNote) {
        out.writeln('  NOTE: $note');
      }
      out.writeln('backtrace:');
      for (var i = 0; i < crashing.backtrace.length; i++) {
        out.writeln(
          '      #${i.toString().padLeft(2, '0')} ${crashing.backtrace[i].format()}',
        );
      }
    }
    return out.toString();
  }
}

/// Formats an unsigned 64-bit value as 16 hex digits.
String hex64(int value) =>
    (value >>> 32).toRadixString(16).padLeft(8, '0') +
    (value & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');

const _varint = 0;
const _fixed64 = 1;
const _bytes = 2;
const _fixed32 = 5;

TombstoneSignal _parseSignal(_ProtoReader r) {
  var number = 0, code = 0, senderUid = 0, senderPid = 0, faultAddress = 0;
  var name = '', codeName = '';
  var hasSender = false, hasFaultAddress = false;
  while (!r.isDone) {
    final (field, wire) = r.readTag();
    switch (field) {
      case 1 when wire == _varint:
        number = r.readVarint();
      case 2 when wire == _bytes:
        name = r.readString();
      case 3 when wire == _varint:
        code = r.readVarint();
      case 4 when wire == _bytes:
        codeName = r.readString();
      case 5 when wire == _varint:
        hasSender = r.readVarint() != 0;
      case 6 when wire == _varint:
        senderUid = r.readVarint();
      case 7 when wire == _varint:
        senderPid = r.readVarint();
      case 8 when wire == _varint:
        hasFaultAddress = r.readVarint() != 0;
      case 9 when wire == _varint:
        faultAddress = r.readVarint();
      default:
        r.skip(wire);
    }
  }
  return TombstoneSignal(
    number: number,
    name: name,
    code: code,
    codeName: codeName,
    hasSender: hasSender,
    senderUid: senderUid,
    senderPid: senderPid,
    hasFaultAddress: hasFaultAddress,
    faultAddress: faultAddress,
  );
}

String _parseCause(_ProtoReader r) {
  var text = '';
  while (!r.isDone) {
    final (field, wire) = r.readTag();
    if (field == 1 && wire == _bytes) {
      text = r.readString();
    } else {
      r.skip(wire);
    }
  }
  return text;
}

/// `map<uint32, Thread>` entry: key = 1, value = 2.
TombstoneThread _parseThreadEntry(_ProtoReader r) {
  TombstoneThread? thread;
  var key = 0;
  while (!r.isDone) {
    final (field, wire) = r.readTag();
    if (field == 1 && wire == _varint) {
      key = r.readVarint();
    } else if (field == 2 && wire == _bytes) {
      thread = _parseThread(r.readMessage());
    } else {
      r.skip(wire);
    }
  }
  return thread ??
      TombstoneThread(
        id: key,
        name: '',
        backtrace: const [],
        backtraceNote: const [],
      );
}

TombstoneThread _parseThread(_ProtoReader r) {
  var id = 0;
  var name = '';
  final frames = <TombstoneFrame>[];
  final notes = <String>[];
  while (!r.isDone) {
    final (field, wire) = r.readTag();
    switch (field) {
      case 1 when wire == _varint:
        id = r.readVarint();
      case 2 when wire == _bytes:
        name = r.readString();
      case 4 when wire == _bytes:
        frames.add(_parseFrame(r.readMessage()));
      case 7 when wire == _bytes:
        notes.add(r.readString());
      default:
        r.skip(wire);
    }
  }
  return TombstoneThread(
    id: id,
    name: name,
    backtrace: List.unmodifiable(frames),
    backtraceNote: List.unmodifiable(notes),
  );
}

TombstoneFrame _parseFrame(_ProtoReader r) {
  var relPc = 0, pc = 0, sp = 0, functionOffset = 0, fileMapOffset = 0;
  var functionName = '', fileName = '', buildId = '';
  while (!r.isDone) {
    final (field, wire) = r.readTag();
    switch (field) {
      case 1 when wire == _varint:
        relPc = r.readVarint();
      case 2 when wire == _varint:
        pc = r.readVarint();
      case 3 when wire == _varint:
        sp = r.readVarint();
      case 4 when wire == _bytes:
        functionName = r.readString();
      case 5 when wire == _varint:
        functionOffset = r.readVarint();
      case 6 when wire == _bytes:
        fileName = r.readString();
      case 7 when wire == _varint:
        fileMapOffset = r.readVarint();
      case 8 when wire == _bytes:
        buildId = r.readString();
      default:
        r.skip(wire);
    }
  }
  return TombstoneFrame(
    relPc: relPc,
    pc: pc,
    sp: sp,
    functionName: functionName,
    functionOffset: functionOffset,
    fileName: fileName,
    fileMapOffset: fileMapOffset,
    buildId: buildId,
  );
}

/// Minimal protobuf wire-format reader (proto3, no groups).
class _ProtoReader {
  _ProtoReader(this._data) : _end = _data.length;

  _ProtoReader._slice(this._data, this._pos, this._end);

  final Uint8List _data;
  int _pos = 0;
  final int _end;

  bool get isDone => _pos >= _end;

  (int, int) readTag() {
    final key = readVarint();
    final field = key >>> 3;
    if (field == 0) {
      throw const FormatException('Invalid protobuf field number 0');
    }
    return (field, key & 7);
  }

  int readVarint() {
    var result = 0;
    for (var shift = 0; shift < 70; shift += 7) {
      if (_pos >= _end) throw const FormatException('Truncated varint');
      final byte = _data[_pos++];
      if (shift < 64) result |= (byte & 0x7f) << shift;
      if (byte & 0x80 == 0) return result;
    }
    throw const FormatException('Varint is too long');
  }

  int _readLength() {
    final length = readVarint();
    if (length < 0 || length > _end - _pos) {
      throw const FormatException('Length-delimited field runs past the end');
    }
    return length;
  }

  String readString() {
    final length = _readLength();
    final text = utf8.decode(
      Uint8List.sublistView(_data, _pos, _pos + length),
      allowMalformed: true,
    );
    _pos += length;
    return text;
  }

  _ProtoReader readMessage() {
    final length = _readLength();
    final reader = _ProtoReader._slice(_data, _pos, _pos + length);
    _pos += length;
    return reader;
  }

  void skip(int wireType) {
    switch (wireType) {
      case _varint:
        readVarint();
      case _fixed64:
        _advance(8);
      case _bytes:
        _advance(_readLength());
      case _fixed32:
        _advance(4);
      default:
        throw FormatException('Unsupported protobuf wire type $wireType');
    }
  }

  void _advance(int count) {
    if (count > _end - _pos) throw const FormatException('Truncated field');
    _pos += count;
  }
}
