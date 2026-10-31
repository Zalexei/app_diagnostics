import 'package:flutter/foundation.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'exit_info.dart';
import 'messages.g.dart';
import 'messages.g.dart' as generated show profilingResults;
import 'profiling.dart';
import 'support.dart';

/// The platform layer behind `AndroidDiagnostics`. Replace
/// [AndroidDiagnosticsPlatform.instance] with a fake in your own tests.
abstract class AndroidDiagnosticsPlatform extends PlatformInterface {
  AndroidDiagnosticsPlatform() : super(token: _token);

  static final Object _token = Object();

  static AndroidDiagnosticsPlatform _instance =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? PigeonAndroidDiagnostics()
      : UnsupportedAndroidDiagnostics();

  static AndroidDiagnosticsPlatform get instance => _instance;

  static set instance(AndroidDiagnosticsPlatform instance) {
    PlatformInterface.verify(instance, _token);
    _instance = instance;
  }

  Future<DiagnosticsSupport> getSupport();

  Future<List<ExitInfo>> getExitReasons({
    required int pid,
    required int maxNum,
  });

  Future<List<ExitInfo>> takeNewExitReasons();

  Future<Uint8List?> getTrace(ExitInfo info);

  Future<bool> setProcessStateSummary(Uint8List? summary);

  Future<ProfilingResult> requestProfiling(
    String requestId,
    ProfilingRequest request,
  );

  Future<bool> cancelProfiling(String requestId);

  Future<List<ProfilingTriggerType>> addProfilingTriggers(
    List<ProfilingTrigger> triggers,
  );

  Future<void> removeProfilingTriggers(List<ProfilingTriggerType> types);

  Future<void> clearProfilingTriggers();

  Future<bool> requestRunningSystemTrace(String? tag);

  Future<List<String>> listProfilingFiles();

  Stream<ProfilingResult> get profilingResults;
}

/// Talks to the Kotlin side through Pigeon.
class PigeonAndroidDiagnostics extends AndroidDiagnosticsPlatform {
  PigeonAndroidDiagnostics({
    AndroidDiagnosticsHostApi? api,
    Stream<ProfilingResultMessage>? results,
  }) : _api = api ?? AndroidDiagnosticsHostApi(),
       _results = results;

  final AndroidDiagnosticsHostApi _api;
  final Stream<ProfilingResultMessage>? _results;

  @override
  Future<DiagnosticsSupport> getSupport() async {
    final m = await _api.getSupport();
    return DiagnosticsSupport(
      sdkInt: m.sdkInt,
      sdkIntFull: m.sdkIntFull,
      exitReasons: m.exitReasons,
      nativeTombstones: m.nativeTombstones,
      anrInfo: m.anrInfo,
      profiling: m.profiling,
      profilingTriggers: m.profilingTriggers,
      runningTraceSnapshot: m.runningTraceSnapshot,
    );
  }

  @override
  Future<List<ExitInfo>> getExitReasons({
    required int pid,
    required int maxNum,
  }) async => (await _api.getExitReasons(
    pid,
    maxNum,
  )).map(exitInfoFromMessage).toList();

  @override
  Future<List<ExitInfo>> takeNewExitReasons() async =>
      (await _api.takeNewExitReasons()).map(exitInfoFromMessage).toList();

  @override
  Future<Uint8List?> getTrace(ExitInfo info) =>
      _api.getTrace(info.pid, info.timestamp.millisecondsSinceEpoch);

  @override
  Future<bool> setProcessStateSummary(Uint8List? summary) =>
      _api.setProcessStateSummary(summary);

  @override
  Future<ProfilingResult> requestProfiling(
    String requestId,
    ProfilingRequest request,
  ) async => profilingResultFromMessage(
    await _api.requestProfiling(requestId, profilingRequestToMessage(request)),
  );

  @override
  Future<bool> cancelProfiling(String requestId) =>
      _api.cancelProfiling(requestId);

  @override
  Future<List<ProfilingTriggerType>> addProfilingTriggers(
    List<ProfilingTrigger> triggers,
  ) async {
    final added = await _api.addProfilingTriggers([
      for (final t in triggers)
        ProfilingTriggerMessage(
          triggerType: t.type.code,
          rateLimitingPeriodHours: t.rateLimitingPeriodHours,
        ),
    ]);
    return added.map(ProfilingTriggerType.fromCode).toList();
  }

  @override
  Future<void> removeProfilingTriggers(List<ProfilingTriggerType> types) =>
      _api.removeProfilingTriggers([for (final t in types) t.code]);

  @override
  Future<void> clearProfilingTriggers() => _api.clearProfilingTriggers();

  @override
  Future<bool> requestRunningSystemTrace(String? tag) =>
      _api.requestRunningSystemTrace(tag);

  @override
  Future<List<String>> listProfilingFiles() => _api.listProfilingFiles();

  @override
  Stream<ProfilingResult> get profilingResults =>
      (_results ?? generated.profilingResults()).map(
        profilingResultFromMessage,
      );
}

/// Used outside Android: every call answers "nothing here".
class UnsupportedAndroidDiagnostics extends AndroidDiagnosticsPlatform {
  static const _unsupported = ProfilingResult(
    errorCode: -1,
    errorMessage: 'android_diagnostics works on Android only',
  );

  @override
  Future<DiagnosticsSupport> getSupport() async => DiagnosticsSupport.none;

  @override
  Future<List<ExitInfo>> getExitReasons({
    required int pid,
    required int maxNum,
  }) async => const [];

  @override
  Future<List<ExitInfo>> takeNewExitReasons() async => const [];

  @override
  Future<Uint8List?> getTrace(ExitInfo info) async => null;

  @override
  Future<bool> setProcessStateSummary(Uint8List? summary) async => false;

  @override
  Future<ProfilingResult> requestProfiling(
    String requestId,
    ProfilingRequest request,
  ) async => _unsupported;

  @override
  Future<bool> cancelProfiling(String requestId) async => false;

  @override
  Future<List<ProfilingTriggerType>> addProfilingTriggers(
    List<ProfilingTrigger> triggers,
  ) async => const [];

  @override
  Future<void> removeProfilingTriggers(
    List<ProfilingTriggerType> types,
  ) async {}

  @override
  Future<void> clearProfilingTriggers() async {}

  @override
  Future<bool> requestRunningSystemTrace(String? tag) async => false;

  @override
  Future<List<String>> listProfilingFiles() async => const [];

  @override
  Stream<ProfilingResult> get profilingResults => const Stream.empty();
}

@visibleForTesting
ExitInfo exitInfoFromMessage(ExitInfoMessage m) {
  final anr = m.anrInfo;
  return ExitInfo(
    reasonCode: m.reason,
    status: m.status,
    importanceCode: m.importance,
    timestamp: DateTime.fromMillisecondsSinceEpoch(m.timestamp),
    pid: m.pid,
    processName: m.processName,
    description: m.description,
    pssKb: m.pss,
    rssKb: m.rss,
    processStateSummary: m.processStateSummary,
    hasTrace: m.hasTrace,
    anrInfo: anr == null
        ? null
        : AnrInfo(
            anrType: anr.anrType,
            anrId: anr.anrId,
            timeout: Duration(milliseconds: anr.timeoutMillis),
            userPerceptible: anr.userPerceptible,
          ),
  );
}

@visibleForTesting
ProfilingRequestMessage profilingRequestToMessage(ProfilingRequest r) =>
    ProfilingRequestMessage(
      type: r.type.code,
      tag: r.tag,
      durationMs: r.duration?.inMilliseconds,
      bufferSizeKb: r.bufferSizeKb,
      samplingFrequencyHz: r.samplingFrequencyHz,
      samplingIntervalBytes: r.samplingIntervalBytes,
      trackJavaAllocations: r.trackJavaAllocations,
      ringBuffer: switch (r.bufferFillPolicy) {
        null => null,
        BufferFillPolicy.ringBuffer => true,
        BufferFillPolicy.discard => false,
      },
    );

@visibleForTesting
ProfilingResult profilingResultFromMessage(ProfilingResultMessage m) =>
    ProfilingResult(
      errorCode: m.errorCode,
      errorMessage: m.errorMessage,
      filePath: m.resultFilePath,
      tag: m.tag,
      triggerCode: m.triggerType,
    );
