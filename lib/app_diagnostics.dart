/// Why your app's process died and what it was doing:
///
/// - [AndroidDiagnostics]: ApplicationExitInfo (exit reasons, ANR traces,
///   native tombstones) and on-device profiling with ProfilingManager.
/// - [IosDiagnostics]: MetricKit crash, hang, CPU and disk write reports and
///   daily exit counts.
///
/// Every call is safe on any OS version and on any platform: unsupported
/// features return empty results.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'src/exit_info.dart';
import 'src/ios_diagnostics.dart';
import 'src/platform.dart';
import 'src/profiling.dart';
import 'src/support.dart';
import 'src/tombstone.dart';

export 'src/exit_info.dart';
export 'src/ios_diagnostics.dart';
export 'src/ios_platform.dart'
    show
        IosDiagnosticsPlatform,
        PigeonIosDiagnostics,
        UnsupportedIosDiagnostics;
export 'src/metrickit.dart';
export 'src/platform.dart'
    show
        AndroidDiagnosticsPlatform,
        PigeonAndroidDiagnostics,
        UnsupportedAndroidDiagnostics;
export 'src/profiling.dart';
export 'src/support.dart';
export 'src/tombstone.dart' hide hex64;

/// Android process exit reasons and on-device profiling. See
/// [IosDiagnostics] for iOS.
abstract final class AndroidDiagnostics {
  static AndroidDiagnosticsPlatform get _platform =>
      AndroidDiagnosticsPlatform.instance;

  static int _nextRequestId = 0;

  /// The system keeps at most this many bytes of process state summary.
  static const int maxProcessStateSummaryBytes = 128;

  /// Which features this device supports.
  static Future<DiagnosticsSupport> getSupport() => _platform.getSupport();

  /// Recent deaths of this app's processes, newest first (Android 11+;
  /// empty list on older versions).
  ///
  /// [maxNum] limits the count (0 = all the system kept); [pid] selects one
  /// process (0 = all).
  static Future<List<ExitInfo>> getExitReasons({int maxNum = 0, int pid = 0}) {
    RangeError.checkNotNegative(maxNum, 'maxNum');
    RangeError.checkNotNegative(pid, 'pid');
    return _platform.getExitReasons(pid: pid, maxNum: maxNum);
  }

  /// Exit records that appeared since the previous call, newest first.
  /// The marker is persisted, so each death is returned once across app
  /// launches: call it on startup to report deaths to your backend.
  static Future<List<ExitInfo>> takeNewExitReasons() =>
      _platform.takeNewExitReasons();

  /// Raw trace bytes of [info]: text for ANRs, a protobuf tombstone for
  /// native crashes (API 31+). Null when the system kept nothing (the trace
  /// buffer is shared and circular, so old traces disappear).
  static Future<Uint8List?> getTraceBytes(ExitInfo info) async =>
      info.hasTrace ? _platform.getTrace(info) : null;

  /// The ANR stack dump of [info] (the same text as `/data/anr/traces`).
  static Future<String?> getAnrTrace(ExitInfo info) async {
    if (info.reason != ExitReason.anr) return null;
    final bytes = await getTraceBytes(info);
    return bytes == null ? null : utf8.decode(bytes, allowMalformed: true);
  }

  /// The decoded tombstone of a native crash (Android 12+), or null when
  /// there is none or it cannot be decoded.
  static Future<NativeTombstone?> getNativeTombstone(ExitInfo info) async {
    if (info.reason != ExitReason.crashNative) return null;
    final bytes = await getTraceBytes(info);
    if (bytes == null) return null;
    try {
      return NativeTombstone.parse(bytes);
    } on FormatException {
      return null;
    }
  }

  /// Stores up to 128 bytes that the next launch reads back from
  /// [ExitInfo.processStateSummary] if this process dies: current screen,
  /// experiment flags, game level. Never put personal data here.
  ///
  /// Returns false when unsupported (below Android 11) or throttled by the
  /// system; throws [ArgumentError] if [summary] is longer than 128 bytes.
  static Future<bool> setProcessStateSummary(Uint8List? summary) {
    if (summary != null && summary.length > maxProcessStateSummaryBytes) {
      throw ArgumentError.value(
        summary.length,
        'summary',
        'must be at most $maxProcessStateSummaryBytes bytes',
      );
    }
    return _platform.setProcessStateSummary(summary);
  }

  /// [setProcessStateSummary] with UTF-8 text.
  static Future<bool> setProcessStateSummaryText(String text) =>
      setProcessStateSummary(Uint8List.fromList(utf8.encode(text)));

  /// Starts a profiling request (Android 15+). The returned session's
  /// `result` completes with [ProfilingError.unsupported] on older devices.
  ///
  /// Requests are rate limited by the system. For local testing run
  /// `adb shell device_config put profiling_testing rate_limiter.disabled true`.
  static ProfilingSession startProfiling(ProfilingRequest request) {
    final id = 'p${DateTime.now().microsecondsSinceEpoch}-${_nextRequestId++}';
    return ProfilingSession(
      id,
      request,
      _platform.requestProfiling(id, request),
      () => _platform.cancelProfiling(id),
    );
  }

  /// [startProfiling] and wait for the result.
  static Future<ProfilingResult> profile(ProfilingRequest request) =>
      startProfiling(request).result;

  /// Registers system triggers (Android 16+) and returns the ones this
  /// device accepted; triggers newer than the device are skipped.
  /// Results arrive in [profilingResults].
  static Future<List<ProfilingTriggerType>> addProfilingTriggers(
    List<ProfilingTrigger> triggers,
  ) => _platform.addProfilingTriggers(triggers);

  static Future<void> removeProfilingTriggers(
    List<ProfilingTriggerType> types,
  ) => _platform.removeProfilingTriggers(types);

  static Future<void> clearProfilingTriggers() =>
      _platform.clearProfilingTriggers();

  /// Asks for a snapshot of the background system trace (Android 16 QPR2+).
  /// Register [ProfilingTriggerType.appRequestRunningTrace] first; the
  /// result arrives in [profilingResults]. Returns false when unsupported.
  static Future<bool> requestRunningSystemTrace({String? tag}) =>
      _platform.requestRunningSystemTrace(tag);

  /// Every profiling result delivered to the app while listening: triggered
  /// ones and those of [startProfiling].
  static Stream<ProfilingResult> get profilingResults =>
      _platform.profilingResults;

  /// Profile files the system put into the app's `files/profiling` folder,
  /// newest first, including results delivered while nobody listened.
  static Future<List<String>> listProfilingFiles() =>
      _platform.listProfilingFiles();
}
