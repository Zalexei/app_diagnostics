import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'support/proto_writer.dart';

class FakePlatform extends AndroidDiagnosticsPlatform
    with MockPlatformInterfaceMixin {
  final traces = <int, Uint8List?>{};
  final summaries = <Uint8List?>[];
  final requests = <String, ProfilingRequest>{};
  final cancelled = <String>[];
  final pending = <String, Completer<ProfilingResult>>{};
  final results = StreamController<ProfilingResult>.broadcast();
  List<ExitInfo> exits = [];

  @override
  Future<DiagnosticsSupport> getSupport() async => DiagnosticsSupport.none;

  @override
  Future<List<ExitInfo>> getExitReasons({
    required int pid,
    required int maxNum,
  }) async => exits
      .where((e) => pid == 0 || e.pid == pid)
      .take(maxNum == 0 ? exits.length : maxNum)
      .toList();

  @override
  Future<List<ExitInfo>> takeNewExitReasons() async => exits;

  @override
  Future<Uint8List?> getTrace(ExitInfo info) async => traces[info.pid];

  @override
  Future<bool> setProcessStateSummary(Uint8List? summary) async {
    summaries.add(summary);
    return true;
  }

  @override
  Future<ProfilingResult> requestProfiling(
    String requestId,
    ProfilingRequest request,
  ) {
    requests[requestId] = request;
    return (pending[requestId] = Completer<ProfilingResult>()).future;
  }

  @override
  Future<bool> cancelProfiling(String requestId) async {
    cancelled.add(requestId);
    pending[requestId]?.complete(
      const ProfilingResult(
        errorCode: 0,
        filePath: '/files/profiling/stack.trace',
      ),
    );
    return true;
  }

  @override
  Future<List<ProfilingTriggerType>> addProfilingTriggers(
    List<ProfilingTrigger> triggers,
  ) async => [for (final t in triggers) t.type];

  @override
  Future<void> removeProfilingTriggers(
    List<ProfilingTriggerType> types,
  ) async {}

  @override
  Future<void> clearProfilingTriggers() async {}

  @override
  Future<bool> requestRunningSystemTrace(String? tag) async => true;

  @override
  Future<List<String>> listProfilingFiles() async => ['/files/profiling/a'];

  @override
  Stream<ProfilingResult> get profilingResults => results.stream;
}

ExitInfo exit(int reason, {int pid = 1, bool hasTrace = true}) => ExitInfo(
  reasonCode: reason,
  status: 0,
  importanceCode: 100,
  timestamp: DateTime(2026, 10, 31),
  pid: pid,
  processName: 'p',
  description: null,
  pssKb: 0,
  rssKb: 0,
  processStateSummary: null,
  hasTrace: hasTrace,
  anrInfo: null,
);

void main() {
  late FakePlatform fake;

  setUp(() => AndroidDiagnosticsPlatform.instance = fake = FakePlatform());

  group('exit reasons', () {
    test('forwards filters', () async {
      fake.exits = [exit(6, pid: 1), exit(4, pid: 2), exit(5, pid: 3)];

      expect(await AndroidDiagnostics.getExitReasons(maxNum: 2), hasLength(2));
      expect(
        (await AndroidDiagnostics.getExitReasons(pid: 3)).single.reason,
        ExitReason.crashNative,
      );
      expect(
        () => AndroidDiagnostics.getExitReasons(maxNum: -1),
        throwsRangeError,
      );
    });

    test('getAnrTrace decodes text only for ANRs', () async {
      fake.traces[1] = Uint8List.fromList(
        utf8.encode('----- pid 1 -----\n"main" prio=5'),
      );

      expect(
        await AndroidDiagnostics.getAnrTrace(exit(6)),
        contains('"main" prio=5'),
      );
      expect(await AndroidDiagnostics.getAnrTrace(exit(4)), isNull);
    });

    test('no platform call when the record has no trace', () async {
      fake.traces[1] = Uint8List(3);

      expect(
        await AndroidDiagnostics.getTraceBytes(exit(6, hasTrace: false)),
        isNull,
      );
      expect(await AndroidDiagnostics.getTraceBytes(exit(6)), hasLength(3));
    });

    test(
      'getNativeTombstone parses native crashes and tolerates garbage',
      () async {
        fake.traces[1] = ProtoWriter()
            .varint(5, 77)
            .string(14, 'boom')
            .toBytes();
        fake.traces[2] = Uint8List.fromList([
          0x0a,
          0x7f,
        ]); // length past the end

        final tombstone = await AndroidDiagnostics.getNativeTombstone(exit(5));
        expect(tombstone!.pid, 77);
        expect(tombstone.abortMessage, 'boom');
        expect(
          await AndroidDiagnostics.getNativeTombstone(exit(5, pid: 2)),
          isNull,
        );
        expect(await AndroidDiagnostics.getNativeTombstone(exit(6)), isNull);
      },
    );
  });

  group('process state summary', () {
    test('accepts up to 128 bytes', () async {
      expect(
        await AndroidDiagnostics.setProcessStateSummary(Uint8List(128)),
        isTrue,
      );
      expect(
        await AndroidDiagnostics.setProcessStateSummaryText('screen=home'),
        isTrue,
      );
      expect(await AndroidDiagnostics.setProcessStateSummary(null), isTrue);
      expect(fake.summaries.map((s) => s?.length), [128, 11, null]);
    });

    test('rejects longer summaries before calling the platform', () {
      expect(
        () => AndroidDiagnostics.setProcessStateSummary(Uint8List(129)),
        throwsArgumentError,
      );
      // 43 x 3-byte characters = 129 bytes.
      expect(
        () => AndroidDiagnostics.setProcessStateSummaryText('€' * 43),
        throwsArgumentError,
      );
      expect(fake.summaries, isEmpty);
    });
  });

  group('profiling', () {
    test('sessions get unique ids and stop through cancelProfiling', () async {
      final a = AndroidDiagnostics.startProfiling(
        const ProfilingRequest.stackSampling(duration: Duration(seconds: 30)),
      );
      final b = AndroidDiagnostics.startProfiling(
        const ProfilingRequest.javaHeapDump(),
      );

      expect(a.id, isNot(b.id));
      expect(fake.requests[a.id]!.type, ProfilingType.stackSampling);
      expect(await a.stop(), isTrue);
      expect(fake.cancelled, [a.id]);
      expect((await a.result).filePath, '/files/profiling/stack.trace');
    });

    test('profile() waits for the result', () async {
      final future = AndroidDiagnostics.profile(
        const ProfilingRequest.systemTrace(tag: 'startup'),
      );
      final id = fake.requests.keys.single;
      fake.pending[id]!.complete(
        const ProfilingResult(errorCode: 1, errorMessage: 'rate limited'),
      );

      final result = await future;
      expect(result.isSuccess, isFalse);
      expect(result.error, ProfilingError.rateLimitSystem);
    });

    test('triggered results come through the stream', () async {
      final received = AndroidDiagnostics.profilingResults.first;
      fake.results.add(
        const ProfilingResult(errorCode: 0, filePath: '/f', triggerCode: 2),
      );

      expect((await received).trigger, ProfilingTriggerType.anr);
    });
  });

  group('outside Android', () {
    setUp(
      () =>
          AndroidDiagnosticsPlatform.instance = UnsupportedAndroidDiagnostics(),
    );

    test('everything degrades to empty answers', () async {
      expect(
        await AndroidDiagnostics.getSupport(),
        same(DiagnosticsSupport.none),
      );
      expect(await AndroidDiagnostics.getExitReasons(), isEmpty);
      expect(await AndroidDiagnostics.takeNewExitReasons(), isEmpty);
      expect(await AndroidDiagnostics.setProcessStateSummaryText('x'), isFalse);
      expect(
        await AndroidDiagnostics.addProfilingTriggers([
          const ProfilingTrigger(ProfilingTriggerType.anr),
        ]),
        isEmpty,
      );
      expect(await AndroidDiagnostics.requestRunningSystemTrace(), isFalse);
      expect(await AndroidDiagnostics.listProfilingFiles(), isEmpty);
      expect(await AndroidDiagnostics.profilingResults.isEmpty, isTrue);
      final result = await AndroidDiagnostics.profile(
        const ProfilingRequest.javaHeapDump(),
      );
      expect(result.error, ProfilingError.unsupported);
    });
  });
}
