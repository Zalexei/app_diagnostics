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
  final bool exitReasons;
  final bool nativeTombstones;
  final bool anrInfo;
  final bool profiling;
  final bool profilingTriggers;
  final bool runningTraceSnapshot;

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
