import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/proto_writer.dart';

ProtoWriter frame(
  int relPc,
  String file, {
  String fn = '',
  int offset = 0,
  String buildId = '',
}) {
  final w = ProtoWriter()
      .varint(1, relPc)
      .varint(2, relPc + 0x7000000000)
      .varint(3, 0x7ff0000000);
  if (fn.isNotEmpty) w.string(4, fn);
  if (offset != 0) w.varint(5, offset);
  w.string(6, file);
  if (buildId.isNotEmpty) w.string(8, buildId);
  return w;
}

ProtoWriter thread(int id, String name, List<ProtoWriter> frames) {
  final w = ProtoWriter().varint(1, id).string(2, name);
  for (final f in frames) {
    w.message(4, f);
  }
  return w;
}

/// A tombstone shaped like the one `__android_log_assert` produces on arm64.
ProtoWriter abortTombstone() => ProtoWriter()
    .varint(1, 1) // arm64
    .string(2, 'google/sdk_gphone64_arm64/emu64a:17/CP1A/1:userdebug/dev-keys')
    .string(3, '0')
    .string(4, '2026-10-31 12:00:00.000000000+0000')
    .varint(5, 4242)
    .varint(6, 4242)
    .varint(7, 10190)
    .string(8, 'u:r:untrusted_app:s0')
    .string(9, 'io.github.zalexei.app_diagnostics_example')
    .message(
      10,
      ProtoWriter()
          .varint(1, 6)
          .string(2, 'SIGABRT')
          .varint(3, -6) // SI_TKILL, negative int32 as a 10-byte varint
          .string(4, 'SI_TKILL')
          .varint(5, 1)
          .varint(6, 10190)
          .varint(7, 4242),
    )
    .string(14, 'crash_lab: native crash from Dart FFI')
    .message(15, ProtoWriter().string(1, 'null pointer dereference'))
    .message(
      16,
      ProtoWriter()
          .varint(1, 4242)
          .message(
            2,
            thread(4242, 'main', [
              frame(
                0x5c8b4,
                '/apex/com.android.runtime/lib64/bionic/libc.so',
                fn: 'abort',
                offset: 164,
                buildId: 'abc123',
              ),
              frame(
                0x7a10,
                '/system/lib64/liblog.so',
                fn: '__android_log_assert',
                offset: 228,
              ),
              frame(0x1234, '[anon:dart-code]'),
            ]),
          ),
    )
    .message(
      16,
      ProtoWriter()
          .varint(1, 4250)
          .message(
            2,
            thread(4250, 'RenderThread', [
              frame(0x10, '/system/lib64/libhwui.so'),
            ]),
          ),
    )
    .varint(20, 42);

void main() {
  group('NativeTombstone.parse', () {
    test('decodes process, signal, abort message and threads', () {
      final t = NativeTombstone.parse(abortTombstone().toBytes());

      expect(t.arch, TombstoneArch.arm64);
      expect(t.pid, 4242);
      expect(t.tid, 4242);
      expect(t.uid, 10190);
      expect(t.commandLine, ['io.github.zalexei.app_diagnostics_example']);
      expect(t.processUptime, const Duration(seconds: 42));
      expect(t.abortMessage, 'crash_lab: native crash from Dart FFI');
      expect(t.causes, ['null pointer dereference']);
      expect(t.signal!.name, 'SIGABRT');
      expect(t.signal!.number, 6);
      expect(t.signal!.code, -6);
      expect(t.signal!.hasSender, isTrue);
      expect(t.signal!.senderPid, 4242);
      expect(t.threads.keys, unorderedEquals([4242, 4250]));
      expect(t.crashingThread!.name, 'main');
      expect(t.crashingThread!.backtrace, hasLength(3));
      final top = t.crashingThread!.backtrace.first;
      expect(top.functionName, 'abort');
      expect(top.functionOffset, 164);
      expect(top.relPc, 0x5c8b4);
      expect(top.buildId, 'abc123');
    });

    test('toText looks like a debuggerd report', () {
      final text = NativeTombstone.parse(abortTombstone().toBytes()).toText();

      expect(text, contains("ABI: 'arm64'"));
      expect(
        text,
        contains(
          'pid: 4242, tid: 4242, name: main  >>> io.github.zalexei.app_diagnostics_example <<<',
        ),
      );
      expect(
        text,
        contains(
          'signal 6 (SIGABRT), code -6 (SI_TKILL from pid 4242, uid 10190), fault addr --------',
        ),
      );
      expect(
        text,
        contains("Abort message: 'crash_lab: native crash from Dart FFI'"),
      );
      expect(
        text,
        contains(
          '#00 pc 000000000005c8b4  /apex/com.android.runtime/lib64/bionic/libc.so (abort+164) (BuildId: abc123)',
        ),
      );
      expect(text, contains('#02 pc 0000000000001234  [anon:dart-code]'));
    });

    test('prints the fault address of a segfault', () {
      final bytes = ProtoWriter()
          .varint(5, 1)
          .varint(6, 1)
          .message(
            10,
            ProtoWriter()
                .varint(1, 11)
                .string(2, 'SIGSEGV')
                .varint(3, 1)
                .string(4, 'SEGV_MAPERR')
                .varint(8, 1)
                .varint(9, 0),
          )
          .toBytes();

      final text = NativeTombstone.parse(bytes).toText();

      expect(
        text,
        contains(
          'signal 11 (SIGSEGV), code 1 (SEGV_MAPERR), fault addr 0x0000000000000000',
        ),
      );
    });

    test('keeps 64-bit addresses with the top bit set', () {
      final tagged = -0x0100000000000000 + 0x1234; // 0xff00000000001234
      final bytes = ProtoWriter()
          .varint(6, 7)
          .message(
            16,
            ProtoWriter()
                .varint(1, 7)
                .message(2, thread(7, 't', [frame(tagged, 'libx.so')])),
          )
          .toBytes();

      final t = NativeTombstone.parse(bytes);

      expect(
        t.crashingThread!.backtrace.single.format(),
        startsWith('pc ff00000000001234  libx.so'),
      );
    });

    test('skips unknown fields of every wire type', () {
      final bytes = ProtoWriter()
          .varint(99, 5)
          .fixed64(98)
          .fixed32(97)
          .string(96, 'future field')
          .message(17, ProtoWriter().string(1, 'memory mapping, ignored'))
          .varint(5, 77)
          .toBytes();

      expect(NativeTombstone.parse(bytes).pid, 77);
    });

    test('defaults when fields are absent', () {
      final t = NativeTombstone.parse(const []);

      expect(t.arch, TombstoneArch.arm32); // proto3 default enum value
      expect(t.signal, isNull);
      expect(t.crashingThread, isNull);
      expect(t.toText(), contains('pid: 0, tid: 0, name: ?  >>> ? <<<'));
    });

    test('unknown architecture codes map to unknown', () {
      expect(
        NativeTombstone.parse(ProtoWriter().varint(1, 42).toBytes()).arch,
        TombstoneArch.unknown,
      );
    });

    test('rejects truncated input', () {
      final bytes = abortTombstone().toBytes();

      // Cuts into the last thread entry (cutting 3 bytes would drop a whole field).
      expect(
        () => NativeTombstone.parse(bytes.sublist(0, bytes.length - 5)),
        throwsFormatException,
      );
      expect(() => NativeTombstone.parse([0x08, 0x80]), throwsFormatException);
      expect(
        () => NativeTombstone.parse([0x0b]),
        throwsFormatException,
      ); // group start
    });
  });
}
