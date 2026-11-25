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
  /// Constructs the platform; subclasses must extend (not implement) this
  /// class so the instance token can be verified.
  AndroidDiagnosticsPlatform() : super(token: _token);

  static final Object _token = Object();

  static AndroidDiagnosticsPlatform _instance =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? PigeonAndroidDiagnostics()
      : UnsupportedAndroidDiagnostics();

  /// The implementation in use: [PigeonAndroidDiagnostics] on Android,
  /// [UnsupportedAndroidDiagnostics] elsewhere.
  static AndroidDiagnosticsPlatform get instance => _instance;

  /// Replaces the implementation, for example with a fake in tests.
  static set instance(AndroidDiagnosticsPlatform instance) {
    PlatformInterface.verify(instance, _token);
    _instance = instance;
  }

  /// Reports which diagnostics features this device offers.
  Future<DiagnosticsSupport> getSupport();

  /// Returns this app's historical process exit records, newest first.
  ///
  /// [pid] selects one process (0 = all); [maxNum] limits the count
  /// (0 = all the system kept).
  Future<List<ExitInfo>> getExitReasons({
    required int pid,
    required int maxNum,
  });

  /// Returns exit records newer than the previous call; the marker is
  /// persisted across launches.
  Future<List<ExitInfo>> takeNewExitReasons();

  /// Returns the raw trace bytes (ANR dump or tombstone) of [info], or null
  /// when the system kept none.
  Future<Uint8List?> getTrace(ExitInfo info);

  /// Stores [summary] to be reported in this process's future exit record;
  /// returns false when unsupported or rejected.
  Future<bool> setProcessStateSummary(Uint8List? summary);

  /// Runs a profiling [request] identified by [requestId] and completes
  /// with its result.
  Future<ProfilingResult> requestProfiling(
    String requestId,
    ProfilingRequest request,
  );

  /// Stops the running request [requestId] early; returns false when no
  /// such request is pending.
  Future<bool> cancelProfiling(String requestId);

  /// Registers system profiling [triggers] and returns the types this
  /// device accepted.
  Future<List<ProfilingTriggerType>> addProfilingTriggers(
    List<ProfilingTrigger> triggers,
  );

  /// Unregisters the triggers of the given [types].
  Future<void> removeProfilingTriggers(List<ProfilingTriggerType> types);

  /// Unregisters all profiling triggers of this app.
  Future<void> clearProfilingTriggers();

  /// Asks the system for a snapshot of the background system trace;
  /// returns false when unsupported.
  Future<bool> requestRunningSystemTrace(String? tag);

  /// Returns paths of the profile files the system delivered to the app.
  Future<List<String>> listProfilingFiles();

  /// Every profiling result delivered to the app, requested or triggered.
  Stream<ProfilingResult> get profilingResults;
}

/// Talks to the Kotlin side through Pigeon.
class PigeonAndroidDiagnostics extends AndroidDiagnosticsPlatform {
  /// Creates the Pigeon implementation; [api] and [results] can be
  /// overridden in tests.
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

  /// One stream for all listeners: every new EventChannel stream would take
  /// the channel over from the previous one.
  @override
  late final Stream<ProfilingResult> profilingResults =
      (_results ?? generated.profilingResults()).map(
        profilingResultFromMessage,
      );
}

/// Used outside Android: every call answers "nothing here".
class UnsupportedAndroidDiagnostics extends AndroidDiagnosticsPlatform {
  static const _unsupported = ProfilingResult(
    errorCode: -1,
    errorMessage: 'ProfilingManager is available on Android only',
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

/// Converts a Pigeon [ExitInfoMessage] to an [ExitInfo].
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

/// Converts a [ProfilingRequest] to its Pigeon message.
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

/// Converts a Pigeon [ProfilingResultMessage] to a [ProfilingResult].
@visibleForTesting
ProfilingResult profilingResultFromMessage(ProfilingResultMessage m) =>
    ProfilingResult(
      errorCode: m.errorCode,
      errorMessage: m.errorMessage,
      filePath: m.resultFilePath,
      tag: m.tag,
      triggerCode: m.triggerType,
    );
