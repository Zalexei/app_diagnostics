import 'dart:convert';
import 'dart:typed_data';

/// Why a process died: `ApplicationExitInfo.REASON_*`.
enum ExitReason {
  /// `REASON_UNKNOWN`: the reason is unknown or newer than this plugin.
  unknown(0, 'Unknown'),

  /// `REASON_EXIT_SELF`: the process exited by itself, e.g. via `System.exit`;
  /// the exit code is in [ExitInfo.status].
  exitSelf(1, 'Exited by itself (System.exit)'),

  /// `REASON_SIGNALED`: the process was killed by an OS signal; the signal
  /// number is in [ExitInfo.status].
  signaled(2, 'Killed by an OS signal'),

  /// `REASON_LOW_MEMORY`: killed by the system low memory killer.
  lowMemory(3, 'Killed by the low memory killer'),

  /// `REASON_CRASH`: an uncaught Java/Kotlin exception.
  crash(4, 'Java/Kotlin crash (uncaught exception)'),

  /// `REASON_CRASH_NATIVE`: a native crash (fatal signal in native code).
  crashNative(5, 'Native crash'),

  /// `REASON_ANR`: killed because the app was not responding.
  anr(6, 'ANR: application not responding'),

  /// `REASON_INITIALIZATION_FAILURE`: the process failed during initialization.
  initializationFailure(7, 'Initialization failure'),

  /// `REASON_PERMISSION_CHANGE`: killed because a runtime permission changed.
  permissionChange(8, 'A runtime permission changed'),

  /// `REASON_EXCESSIVE_RESOURCE_USAGE`: killed for excessive resource usage.
  excessiveResourceUsage(9, 'Excessive resource usage'),

  /// `REASON_USER_REQUESTED`: stopped on the user's request, e.g. force stop.
  userRequested(
    10,
    'Stopped by the user (force stop, swipe from recents, ...)',
  ),

  /// `REASON_USER_STOPPED`: killed because the device user it ran under was
  /// stopped.
  userStopped(11, 'The device user was stopped'),

  /// `REASON_DEPENDENCY_DIED`: killed because a process it depends on died.
  dependencyDied(12, 'A dependency process died'),

  /// `REASON_OTHER`: killed by the system for a reason not covered above.
  other(13, 'Killed by the system for another reason'),

  /// `REASON_FREEZER`: killed by the app freezer.
  freezer(14, 'Killed by the app freezer'),

  /// `REASON_PACKAGE_STATE_CHANGE`: the package was disabled or enabled.
  packageStateChange(15, 'The package was disabled or enabled'),

  /// `REASON_PACKAGE_UPDATED`: killed because the package was updated.
  packageUpdated(16, 'The package was updated'),

  /// Killed for exceeding the system memory limits (code 17).
  memoryLimiter(17, 'Exceeded the system memory limits'),

  /// Killed for violating a system resource anomaly rule (code 18).
  anomaly(18, 'Violated a system resource anomaly rule');

  const ExitReason(this.code, this.description);

  /// The `ApplicationExitInfo.REASON_*` constant.
  final int code;

  /// Short English description.
  final String description;

  /// Maps an Android constant to the enum; values added after this plugin
  /// version map to [unknown] (the raw code stays in [ExitInfo.reasonCode]).
  static ExitReason fromCode(int code) {
    for (final reason in values) {
      if (reason.code == code) return reason;
    }
    return unknown;
  }
}

/// `ActivityManager.RunningAppProcessInfo.IMPORTANCE_*` before the death.
enum ProcessImportance {
  /// `IMPORTANCE_FOREGROUND`: running the UI the user is interacting with.
  foreground(100),

  /// `IMPORTANCE_FOREGROUND_SERVICE`: running a foreground service.
  foregroundService(125),

  /// `IMPORTANCE_VISIBLE`: visible to the user but not in the foreground.
  visible(200),

  /// `IMPORTANCE_PERCEPTIBLE`: not visible, but doing something the user
  /// notices, such as playing audio.
  perceptible(230),

  /// `IMPORTANCE_SERVICE`: running a background service.
  service(300),

  /// `IMPORTANCE_TOP_SLEEPING`: the top app while the device is asleep.
  topSleeping(325),

  /// `IMPORTANCE_CANT_SAVE_STATE`: a heavy-weight process that cannot save
  /// its state.
  cantSaveState(350),

  /// `IMPORTANCE_CACHED`: a cached process not currently needed.
  cached(400),

  /// `IMPORTANCE_EMPTY`: an empty process (deprecated on Android).
  empty(500),

  /// `IMPORTANCE_GONE`: the process no longer exists.
  gone(1000),

  /// A value this plugin does not recognize.
  unknown(-1);

  const ProcessImportance(this.code);

  /// The raw `IMPORTANCE_*` constant, or -1 for [unknown].
  final int code;

  /// Maps an Android `IMPORTANCE_*` constant to the enum; unrecognized
  /// values map to [unknown].
  static ProcessImportance fromCode(int code) {
    for (final importance in values) {
      if (importance.code == code) return importance;
    }
    return unknown;
  }
}

/// Details of an ANR, Android 17 (API 37) and newer.
class AnrInfo {
  /// Creates ANR details.
  const AnrInfo({
    required this.anrType,
    required this.anrId,
    required this.timeout,
    required this.userPerceptible,
  });

  /// `ApplicationExitInfo.AnrInfo.getAnrType()`, raw platform value.
  final int anrType;

  /// `ApplicationExitInfo.AnrInfo.getAnrId()`, raw platform value.
  final int anrId;

  /// How long the system waited before declaring the ANR.
  final Duration timeout;

  /// Whether the ANR dialog was shown to the user.
  final bool userPerceptible;

  /// JSON-friendly map of these details.
  Map<String, Object?> toJson() => {
    'anrType': anrType,
    'anrId': anrId,
    'timeoutMs': timeout.inMilliseconds,
    'userPerceptible': userPerceptible,
  };
}

/// One historical process death of this app: `android.app.ApplicationExitInfo`.
class ExitInfo {
  /// Creates an exit record; normally obtained from the plugin, not built by
  /// hand.
  const ExitInfo({
    required this.reasonCode,
    required this.status,
    required this.importanceCode,
    required this.timestamp,
    required this.pid,
    required this.processName,
    required this.description,
    required this.pssKb,
    required this.rssKb,
    required this.processStateSummary,
    required this.hasTrace,
    required this.anrInfo,
  });

  /// Raw `ApplicationExitInfo.getReason()`.
  final int reasonCode;

  /// Exit status for [ExitReason.exitSelf], signal number for [ExitReason.signaled].
  final int status;

  /// Raw `ApplicationExitInfo.getImportance()`.
  final int importanceCode;

  /// When the process died.
  final DateTime timestamp;

  /// Process id of the process that died.
  final int pid;

  /// Name of the process that died.
  final String processName;

  /// Free-form text from the system, e.g. `crash`, `user request after error`.
  final String? description;

  /// Last sampled proportional set size, KB (0 if never sampled).
  final int pssKb;

  /// Last sampled resident set size, KB (0 if never sampled).
  final int rssKb;

  /// Bytes the process stored with `setProcessStateSummary` before dying.
  final Uint8List? processStateSummary;

  /// Whether the system kept a trace: an ANR stack dump, or (API 31+) a
  /// native crash tombstone.
  final bool hasTrace;

  /// ANR details, Android 17+ only.
  final AnrInfo? anrInfo;

  /// [reasonCode] as an [ExitReason].
  ExitReason get reason => ExitReason.fromCode(reasonCode);

  /// [importanceCode] as a [ProcessImportance].
  ProcessImportance get importance =>
      ProcessImportance.fromCode(importanceCode);

  /// [processStateSummary] decoded as UTF-8 (malformed bytes are replaced).
  String? get processStateSummaryText {
    final bytes = processStateSummary;
    return bytes == null ? null : utf8.decode(bytes, allowMalformed: true);
  }

  /// The app was killed or crashed because of its own problem
  /// (crash, native crash, ANR, low memory, excessive resource usage, ...).
  bool get isAppProblem => const {
    ExitReason.crash,
    ExitReason.crashNative,
    ExitReason.anr,
    ExitReason.lowMemory,
    ExitReason.excessiveResourceUsage,
    ExitReason.initializationFailure,
    ExitReason.memoryLimiter,
    ExitReason.anomaly,
  }.contains(reason);

  /// JSON-friendly map, handy for sending to analytics or a crash backend.
  Map<String, Object?> toJson() => {
    'reason': reason.name,
    'reasonCode': reasonCode,
    'status': status,
    'importance': importance.name,
    'importanceCode': importanceCode,
    'timestamp': timestamp.toUtc().toIso8601String(),
    'pid': pid,
    'processName': processName,
    'description': description,
    'pssKb': pssKb,
    'rssKb': rssKb,
    'processStateSummary': processStateSummaryText,
    'hasTrace': hasTrace,
    if (anrInfo != null) 'anrInfo': anrInfo!.toJson(),
  };

  @override
  String toString() =>
      'ExitInfo(${reason.name}, pid $pid, ${timestamp.toIso8601String()}, '
      '${importance.name}, description: $description)';
}
