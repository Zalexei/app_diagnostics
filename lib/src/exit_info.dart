import 'dart:convert';
import 'dart:typed_data';

/// Why a process died: `ApplicationExitInfo.REASON_*`.
enum ExitReason {
  unknown(0, 'Unknown'),
  exitSelf(1, 'Exited by itself (System.exit)'),
  signaled(2, 'Killed by an OS signal'),
  lowMemory(3, 'Killed by the low memory killer'),
  crash(4, 'Java/Kotlin crash (uncaught exception)'),
  crashNative(5, 'Native crash'),
  anr(6, 'ANR: application not responding'),
  initializationFailure(7, 'Initialization failure'),
  permissionChange(8, 'A runtime permission changed'),
  excessiveResourceUsage(9, 'Excessive resource usage'),
  userRequested(
    10,
    'Stopped by the user (force stop, swipe from recents, ...)',
  ),
  userStopped(11, 'The device user was stopped'),
  dependencyDied(12, 'A dependency process died'),
  other(13, 'Killed by the system for another reason'),
  freezer(14, 'Killed by the app freezer'),
  packageStateChange(15, 'The package was disabled or enabled'),
  packageUpdated(16, 'The package was updated'),
  memoryLimiter(17, 'Exceeded the system memory limits'),
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
  foreground(100),
  foregroundService(125),
  visible(200),
  perceptible(230),
  service(300),
  topSleeping(325),
  cantSaveState(350),
  cached(400),
  empty(500),
  gone(1000),
  unknown(-1);

  const ProcessImportance(this.code);

  final int code;

  static ProcessImportance fromCode(int code) {
    for (final importance in values) {
      if (importance.code == code) return importance;
    }
    return unknown;
  }
}

/// Details of an ANR, Android 17 (API 37) and newer.
class AnrInfo {
  const AnrInfo({
    required this.anrType,
    required this.anrId,
    required this.timeout,
    required this.userPerceptible,
  });

  /// `ApplicationExitInfo.AnrInfo.getAnrType()`, raw platform value.
  final int anrType;
  final int anrId;

  /// How long the system waited before declaring the ANR.
  final Duration timeout;

  /// Whether the ANR dialog was shown to the user.
  final bool userPerceptible;

  Map<String, Object?> toJson() => {
    'anrType': anrType,
    'anrId': anrId,
    'timeoutMs': timeout.inMilliseconds,
    'userPerceptible': userPerceptible,
  };
}

/// One historical process death of this app: `android.app.ApplicationExitInfo`.
class ExitInfo {
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
  final int pid;
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

  ExitReason get reason => ExitReason.fromCode(reasonCode);

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
