import 'dart:async';
import 'dart:typed_data';

import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:app_diagnostics/src/messages.g.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for the generated Pigeon API (and so for the Kotlin side).
class FakeHost extends AndroidDiagnosticsHostApi {
  final calls = <String>[];
  ProfilingRequestMessage? lastRequest;
  List<ProfilingTriggerMessage>? lastTriggers;
  Uint8List? lastSummary;
  (int, int)? lastTraceKey;

  @override
  Future<SupportMessage> getSupport() async => SupportMessage(
    sdkInt: 36,
    sdkIntFull: 3600001,
    exitReasons: true,
    nativeTombstones: true,
    anrInfo: false,
    profiling: true,
    profilingTriggers: true,
    runningTraceSnapshot: true,
  );

  @override
  Future<List<ExitInfoMessage>> getExitReasons(int pid, int maxNum) async {
    calls.add('getExitReasons($pid, $maxNum)');
    return [
      ExitInfoMessage(
        reason: 6,
        status: 0,
        importance: 100,
        timestamp: 1793443795324,
        pid: 4242,
        processName: 'com.example',
        description: 'user request after error: Input dispatching timed out',
        pss: 1,
        rss: 336784,
        processStateSummary: Uint8List.fromList('lab=anr'.codeUnits),
        hasTrace: true,
        anrInfo: AnrInfoMessage(
          anrType: 5,
          anrId: 2707,
          timeoutMillis: 15070,
          userPerceptible: true,
        ),
      ),
    ];
  }

  @override
  Future<List<ExitInfoMessage>> takeNewExitReasons() async => [];

  @override
  Future<Uint8List?> getTrace(int pid, int timestamp) async {
    lastTraceKey = (pid, timestamp);
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<bool> setProcessStateSummary(Uint8List? summary) async {
    lastSummary = summary;
    return true;
  }

  @override
  Future<ProfilingResultMessage> requestProfiling(
    String requestId,
    ProfilingRequestMessage request,
  ) async {
    lastRequest = request;
    return ProfilingResultMessage(
      errorCode: 0,
      resultFilePath:
          '/data/user/0/com.example/files/profiling/trace.perfetto-trace',
      tag: request.tag,
      triggerType: 0,
    );
  }

  @override
  Future<bool> cancelProfiling(String requestId) async => false;

  @override
  Future<List<int>> addProfilingTriggers(
    List<ProfilingTriggerMessage> triggers,
  ) async {
    lastTriggers = triggers;
    return [2];
  }

  @override
  Future<void> removeProfilingTriggers(List<int> triggerTypes) async =>
      calls.add('remove($triggerTypes)');

  @override
  Future<void> clearProfilingTriggers() async => calls.add('clear');

  @override
  Future<bool> requestRunningSystemTrace(String? tag) async => tag == 'snap';

  @override
  Future<List<String>> listProfilingFiles() async => ['/a', '/b'];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeHost host;
  late PigeonAndroidDiagnostics platform;

  setUp(() {
    host = FakeHost();
    platform = PigeonAndroidDiagnostics(
      api: host,
      results: Stream.value(
        ProfilingResultMessage(errorCode: 0, triggerType: 7),
      ),
    );
    AndroidDiagnosticsPlatform.instance = platform;
  });

  test('Android is the default platform', () {
    expect(PigeonAndroidDiagnostics(), isA<AndroidDiagnosticsPlatform>());
  });

  test('support flags survive the channel', () async {
    final support = await AndroidDiagnostics.getSupport();

    expect(support.sdkIntFull, 3600001);
    expect(support.supportsTrigger(ProfilingTriggerType.killRecents), isTrue);
    expect(support.supportsTrigger(ProfilingTriggerType.oom), isFalse);
  });

  test('exit records are converted field by field', () async {
    final info = (await AndroidDiagnostics.getExitReasons(
      maxNum: 5,
      pid: 4242,
    )).single;

    expect(host.calls, ['getExitReasons(4242, 5)']);
    expect(info.reason, ExitReason.anr);
    expect(info.importance, ProcessImportance.foreground);
    expect(info.timestamp.millisecondsSinceEpoch, 1793443795324);
    expect(info.rssKb, 336784);
    expect(info.processStateSummaryText, 'lab=anr');
    expect(info.anrInfo!.timeout, const Duration(milliseconds: 15070));
    expect(info.anrInfo!.userPerceptible, isTrue);
  });

  test('traces are looked up by pid and timestamp', () async {
    final info = (await AndroidDiagnostics.getExitReasons()).single;

    expect(await AndroidDiagnostics.getTraceBytes(info), [1, 2, 3]);
    expect(host.lastTraceKey, (4242, 1793443795324));
  });

  test('summary bytes reach the host', () async {
    await AndroidDiagnostics.setProcessStateSummaryText('level=7');

    expect(String.fromCharCodes(host.lastSummary!), 'level=7');
  });

  test('profiling requests carry every parameter', () async {
    final result = await AndroidDiagnostics.profile(
      const ProfilingRequest.systemTrace(
        tag: 'checkout',
        duration: Duration(seconds: 10),
        bufferSizeKb: 32768,
        bufferFillPolicy: BufferFillPolicy.ringBuffer,
      ),
    );

    final m = host.lastRequest!;
    expect(m.type, 4);
    expect(m.tag, 'checkout');
    expect(m.durationMs, 10000);
    expect(m.bufferSizeKb, 32768);
    expect(m.ringBuffer, isTrue);
    expect(m.samplingFrequencyHz, isNull);
    expect(result.isSuccess, isTrue);
    expect(result.tag, 'checkout');
  });

  test('heap profile parameters', () async {
    await AndroidDiagnostics.profile(
      const ProfilingRequest.heapProfile(
        samplingIntervalBytes: 4096,
        trackJavaAllocations: true,
      ),
    );

    expect(host.lastRequest!.type, 2);
    expect(host.lastRequest!.samplingIntervalBytes, 4096);
    expect(host.lastRequest!.trackJavaAllocations, isTrue);
    expect(host.lastRequest!.ringBuffer, isNull);
  });

  test('triggers are sent as codes and accepted ones come back', () async {
    final accepted = await AndroidDiagnostics.addProfilingTriggers([
      const ProfilingTrigger(
        ProfilingTriggerType.anr,
        rateLimitingPeriodHours: 6,
      ),
      const ProfilingTrigger(ProfilingTriggerType.oom),
    ]);
    await AndroidDiagnostics.removeProfilingTriggers([
      ProfilingTriggerType.oom,
    ]);
    await AndroidDiagnostics.clearProfilingTriggers();

    expect(
      host.lastTriggers!.map((t) => (t.triggerType, t.rateLimitingPeriodHours)),
      [(2, 6), (7, null)],
    );
    expect(accepted, [ProfilingTriggerType.anr]);
    expect(host.calls, ['remove([7])', 'clear']);
  });

  test('misc calls', () async {
    expect(
      await AndroidDiagnostics.requestRunningSystemTrace(tag: 'snap'),
      isTrue,
    );
    expect(await AndroidDiagnostics.listProfilingFiles(), ['/a', '/b']);
    expect(
      (await AndroidDiagnostics.profilingResults.single).trigger,
      ProfilingTriggerType.oom,
    );
  });
}
