import 'profiling.dart';

/// Which diagnostics this device offers.
///
/// | Feature | Android |
/// |---|---|
/// | [exitReasons], process state summary, ANR traces | 11 (API 30) |
/// | [nativeTombstones] | 12 (API 31) |
/// | [profiling] | 15 (API 35) |
/// | [profilingTriggers] | 16 (API 36) |
/// | [runningTraceSnapshot] | 16 QPR2 (API 36.1) |
/// | [anrInfo] | 17 (API 37) |
class DiagnosticsSupport {
  /// Creates a support report; normally obtained from
  /// `AndroidDiagnostics.getSupport`.
  const DiagnosticsSupport({
    required this.sdkInt,
    required this.sdkIntFull,
    required this.exitReasons,
    required this.nativeTombstones,
    required this.anrInfo,
    required this.profiling,
    required this.profilingTriggers,
    required this.runningTraceSnapshot,
  });

  /// Reported on platforms other than Android.
  static const none = DiagnosticsSupport(
    sdkInt: 0,
    sdkIntFull: 0,
    exitReasons: false,
    nativeTombstones: false,
    anrInfo: false,
    profiling: false,
    profilingTriggers: false,
    runningTraceSnapshot: false,
  );

  /// `Build.VERSION.SDK_INT`, 0 outside Android.
  final int sdkInt;

  /// `Build.VERSION.SDK_INT_FULL` (major * 100000 + minor), or
  /// `sdkInt * 100000` before Android 16.
  final int sdkIntFull;

  /// Whether `ApplicationExitInfo` exit reasons are available (Android 11+).
  final bool exitReasons;

  /// Whether native crash tombstones can be read (Android 12+).
  final bool nativeTombstones;

  /// Whether exit records carry extra ANR details (Android 17+).
  final bool anrInfo;

  /// Whether ProfilingManager requests are available (Android 15+).
  final bool profiling;

  /// Whether system profiling triggers can be registered (Android 16+).
  final bool profilingTriggers;

  /// Whether a snapshot of the running system trace can be requested
  /// (Android 16 QPR2+).
  final bool runningTraceSnapshot;

  /// Whether this device can register a trigger of [type].
  bool supportsTrigger(ProfilingTriggerType type) =>
      profilingTriggers &&
      type != ProfilingTriggerType.none &&
      type != ProfilingTriggerType.unknown &&
      sdkIntFull >= type.minSdkFull;

  @override
  String toString() =>
      'DiagnosticsSupport(sdk $sdkInt, exitReasons: $exitReasons, '
      'nativeTombstones: $nativeTombstones, profiling: $profiling, '
      'triggers: $profilingTriggers, runningTrace: $runningTraceSnapshot, '
      'anrInfo: $anrInfo)';
}
