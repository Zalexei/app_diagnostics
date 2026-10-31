// Pigeon schema for the Dart <-> Kotlin bridge.
// Regenerate with: dart run pigeon --input pigeons/messages.dart
//
// Android constants (reasons, importance, error codes, trigger types) travel
// as raw ints, so records from newer Android versions are never dropped; the
// Dart layer maps them to enums with an `unknown` fallback.
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    kotlinOut:
        'android/src/main/kotlin/io/github/zalexei/app_diagnostics/Messages.g.kt',
    kotlinOptions: KotlinOptions(
      package: 'io.github.zalexei.app_diagnostics',
    ),
    dartPackageName: 'app_diagnostics',
  ),
)
/// What the current device supports. Computed from Build.VERSION.
class SupportMessage {
  SupportMessage({
    required this.sdkInt,
    required this.sdkIntFull,
    required this.exitReasons,
    required this.nativeTombstones,
    required this.anrInfo,
    required this.profiling,
    required this.profilingTriggers,
    required this.runningTraceSnapshot,
  });

  int sdkInt;

  /// Build.VERSION.SDK_INT_FULL (major * 100000 + minor); SDK_INT * 100000 before API 36.
  int sdkIntFull;
  bool exitReasons;
  bool nativeTombstones;
  bool anrInfo;
  bool profiling;
  bool profilingTriggers;
  bool runningTraceSnapshot;
}

class AnrInfoMessage {
  AnrInfoMessage({
    required this.anrType,
    required this.anrId,
    required this.timeoutMillis,
    required this.userPerceptible,
  });

  int anrType;
  int anrId;
  int timeoutMillis;
  bool userPerceptible;
}

/// One android.app.ApplicationExitInfo record.
class ExitInfoMessage {
  ExitInfoMessage({
    required this.reason,
    required this.status,
    required this.importance,
    required this.timestamp,
    required this.pid,
    required this.processName,
    required this.description,
    required this.pss,
    required this.rss,
    required this.processStateSummary,
    required this.hasTrace,
    required this.anrInfo,
  });

  int reason;
  int status;
  int importance;
  int timestamp;
  int pid;
  String processName;
  String? description;
  int pss;
  int rss;
  Uint8List? processStateSummary;
  bool hasTrace;
  AnrInfoMessage? anrInfo;
}

class ProfilingRequestMessage {
  ProfilingRequestMessage({
    required this.type,
    this.tag,
    this.durationMs,
    this.bufferSizeKb,
    this.samplingFrequencyHz,
    this.samplingIntervalBytes,
    this.trackJavaAllocations,
    this.ringBuffer,
  });

  /// ProfilingManager.PROFILING_TYPE_* value.
  int type;
  String? tag;
  int? durationMs;
  int? bufferSizeKb;
  int? samplingFrequencyHz;
  int? samplingIntervalBytes;
  bool? trackJavaAllocations;
  bool? ringBuffer;
}

class ProfilingResultMessage {
  ProfilingResultMessage({
    required this.errorCode,
    this.errorMessage,
    this.resultFilePath,
    this.tag,
    required this.triggerType,
  });

  /// ProfilingResult.ERROR_* value, or -1 when the device has no ProfilingManager.
  int errorCode;
  String? errorMessage;
  String? resultFilePath;
  String? tag;
  int triggerType;
}

class ProfilingTriggerMessage {
  ProfilingTriggerMessage({
    required this.triggerType,
    this.rateLimitingPeriodHours,
  });

  int triggerType;
  int? rateLimitingPeriodHours;
}

@HostApi()
abstract class AndroidDiagnosticsHostApi {
  SupportMessage getSupport();

  /// ActivityManager.getHistoricalProcessExitReasons for this package.
  @TaskQueue(type: TaskQueueType.serialBackgroundThread)
  List<ExitInfoMessage> getExitReasons(int pid, int maxNum);

  /// Records newer than the previous call; the marker is kept in SharedPreferences.
  @TaskQueue(type: TaskQueueType.serialBackgroundThread)
  List<ExitInfoMessage> takeNewExitReasons();

  /// Bytes of ApplicationExitInfo.getTraceInputStream for the record, or null.
  @TaskQueue(type: TaskQueueType.serialBackgroundThread)
  Uint8List? getTrace(int pid, int timestamp);

  bool setProcessStateSummary(Uint8List? summary);

  @async
  ProfilingResultMessage requestProfiling(
    String requestId,
    ProfilingRequestMessage request,
  );

  bool cancelProfiling(String requestId);

  /// Returns the trigger types that were registered (types newer than the
  /// device are skipped).
  List<int> addProfilingTriggers(List<ProfilingTriggerMessage> triggers);

  void removeProfilingTriggers(List<int> triggerTypes);

  void clearProfilingTriggers();

  bool requestRunningSystemTrace(String? tag);

  /// Paths of files the system delivered to filesDir/profiling.
  @TaskQueue(type: TaskQueueType.serialBackgroundThread)
  List<String> listProfilingFiles();
}

@EventChannelApi()
abstract class AndroidDiagnosticsEventApi {
  /// Every result delivered to this app, triggered or requested.
  ProfilingResultMessage profilingResults();
}
