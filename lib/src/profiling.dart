/// `ProfilingManager.PROFILING_TYPE_*`.
enum ProfilingType {
  /// A full Java heap dump (`.hprof`-like perfetto trace).
  javaHeapDump(1),

  /// Sampled allocations (native by default) over a time window.
  heapProfile(2),

  /// CPU call stack sampling over a time window.
  stackSampling(3),

  /// A Perfetto system trace.
  systemTrace(4);

  const ProfilingType(this.code);

  final int code;
}

/// What a system trace does when its buffer is full.
enum BufferFillPolicy {
  /// Stop recording: keeps the beginning of the window.
  discard,

  /// Overwrite the oldest data: keeps the end of the window.
  ringBuffer,
}

/// A profiling request. Every parameter is optional; the system clamps values
/// to its supported range and uses its defaults for omitted ones.
class ProfilingRequest {
  const ProfilingRequest.javaHeapDump({this.tag, this.bufferSizeKb})
    : type = ProfilingType.javaHeapDump,
      duration = null,
      samplingFrequencyHz = null,
      samplingIntervalBytes = null,
      trackJavaAllocations = null,
      bufferFillPolicy = null;

  const ProfilingRequest.heapProfile({
    this.tag,
    this.duration,
    this.bufferSizeKb,
    this.samplingIntervalBytes,
    this.trackJavaAllocations,
  }) : type = ProfilingType.heapProfile,
       samplingFrequencyHz = null,
       bufferFillPolicy = null;

  const ProfilingRequest.stackSampling({
    this.tag,
    this.duration,
    this.bufferSizeKb,
    this.samplingFrequencyHz,
  }) : type = ProfilingType.stackSampling,
       samplingIntervalBytes = null,
       trackJavaAllocations = null,
       bufferFillPolicy = null;

  const ProfilingRequest.systemTrace({
    this.tag,
    this.duration,
    this.bufferSizeKb,
    this.bufferFillPolicy,
  }) : type = ProfilingType.systemTrace,
       samplingFrequencyHz = null,
       samplingIntervalBytes = null,
       trackJavaAllocations = null;

  final ProfilingType type;

  /// Lowercased (first 20 alphanumeric characters and dashes) into the file name.
  final String? tag;
  final Duration? duration;
  final int? bufferSizeKb;
  final int? samplingFrequencyHz;
  final int? samplingIntervalBytes;

  /// Heap profile: track Java allocations instead of native ones.
  final bool? trackJavaAllocations;
  final BufferFillPolicy? bufferFillPolicy;
}

/// `ProfilingResult.ERROR_*`, plus [unsupported] for devices without
/// ProfilingManager (below Android 15).
enum ProfilingError {
  none(0),
  rateLimitSystem(1),
  rateLimitProcess(2),
  profilingInProgress(3),
  failedExecuting(4),
  failedPostProcessing(5),
  noDiskSpace(6),
  invalidRequest(7),
  unknown(8),
  unsupported(-1);

  const ProfilingError(this.code);

  final int code;

  static ProfilingError fromCode(int code) {
    for (final error in values) {
      if (error.code == code) return error;
    }
    return unknown;
  }
}

/// `ProfilingTrigger.TRIGGER_TYPE_*`: system events that make the system
/// capture a profile on the app's behalf.
enum ProfilingTriggerType {
  /// Used in results that came from [ProfilingRequest]s.
  none(0, 36, 0),

  /// `Activity.reportFullyDrawn()` after a cold start; running trace snapshot.
  appFullyDrawn(1, 36, 0),

  /// An ANR was detected, before the kill; running trace snapshot.
  anr(2, 36, 0),

  /// `requestRunningSystemTrace()`; running trace snapshot.
  appRequestRunningTrace(3, 36, 1),

  /// "Force stop" in App info; running trace snapshot.
  killForceStop(4, 36, 1),

  /// Swiped away from Recents; running trace snapshot.
  killRecents(5, 36, 1),

  /// "Stop" in the Task Manager; running trace snapshot.
  killTaskManager(6, 36, 1),

  /// Java OutOfMemoryError; Java heap dump.
  oom(7, 37, 0),

  /// The system detected anomalous behaviour.
  anomaly(8, 37, 0),

  /// Killed for excessive CPU usage.
  killExcessiveCpuUsage(9, 37, 0),

  /// As early as possible in a cold start.
  coldStart(10, 37, 0),

  /// Behaviour that will become unsupported in future Android versions.
  appCompat(11, 37, 0),

  /// A trigger type added after this plugin version.
  unknown(-1, 1000, 0);

  const ProfilingTriggerType(this.code, this.minSdk, this.minSdkMinor);

  final int code;

  /// Minimum `Build.VERSION.SDK_INT`.
  final int minSdk;

  /// Minimum minor SDK version on top of [minSdk] (Android 16 QPR2 is 36.1).
  final int minSdkMinor;

  /// `Build.VERSION.SDK_INT_FULL` this trigger needs.
  int get minSdkFull => minSdk * 100000 + minSdkMinor;

  static ProfilingTriggerType fromCode(int code) {
    for (final type in values) {
      if (type.code == code) return type;
    }
    return unknown;
  }
}

/// A trigger to register with `addProfilingTriggers`.
class ProfilingTrigger {
  const ProfilingTrigger(this.type, {this.rateLimitingPeriodHours});

  final ProfilingTriggerType type;

  /// At most one result per this many hours for this trigger (the system
  /// also applies its own limits).
  final int? rateLimitingPeriodHours;
}

/// Outcome of a profiling request or a trigger.
class ProfilingResult {
  const ProfilingResult({
    required this.errorCode,
    this.errorMessage,
    this.filePath,
    this.tag,
    this.triggerCode = 0,
  });

  /// Raw `ProfilingResult.getErrorCode()`, -1 when unsupported.
  final int errorCode;
  final String? errorMessage;

  /// Absolute path of the trace in the app's files dir when [isSuccess].
  /// Open it in https://ui.perfetto.dev.
  final String? filePath;
  final String? tag;

  /// Raw `ProfilingResult.getTriggerType()`.
  final int triggerCode;

  ProfilingError get error => ProfilingError.fromCode(errorCode);

  ProfilingTriggerType get trigger =>
      ProfilingTriggerType.fromCode(triggerCode);

  bool get isSuccess => errorCode == 0 && filePath != null;

  @override
  String toString() => isSuccess
      ? 'ProfilingResult(ok, $filePath, trigger: ${trigger.name})'
      : 'ProfilingResult(${error.name}, $errorMessage)';
}

/// A running profiling request.
class ProfilingSession {
  ProfilingSession(this.id, this.request, this.result, this._stop);

  final String id;
  final ProfilingRequest request;

  /// Completes when the system delivers the result (after [stop], the
  /// duration or the system timeout).
  final Future<ProfilingResult> result;
  final Future<bool> Function() _stop;

  /// Ends a continuous profile early; the result still arrives in [result].
  /// Returns false when the request has already finished.
  Future<bool> stop() => _stop();
}
