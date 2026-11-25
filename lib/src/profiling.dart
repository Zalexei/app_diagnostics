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

  /// The matching `ProfilingManager.PROFILING_TYPE_*` constant.
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
  /// Requests a one-shot Java heap dump.
  const ProfilingRequest.javaHeapDump({this.tag, this.bufferSizeKb})
    : type = ProfilingType.javaHeapDump,
      duration = null,
      samplingFrequencyHz = null,
      samplingIntervalBytes = null,
      trackJavaAllocations = null,
      bufferFillPolicy = null;

  /// Requests a heap profile that samples allocations for [duration].
  const ProfilingRequest.heapProfile({
    this.tag,
    this.duration,
    this.bufferSizeKb,
    this.samplingIntervalBytes,
    this.trackJavaAllocations,
  }) : type = ProfilingType.heapProfile,
       samplingFrequencyHz = null,
       bufferFillPolicy = null;

  /// Requests CPU call stack sampling for [duration].
  const ProfilingRequest.stackSampling({
    this.tag,
    this.duration,
    this.bufferSizeKb,
    this.samplingFrequencyHz,
  }) : type = ProfilingType.stackSampling,
       samplingIntervalBytes = null,
       trackJavaAllocations = null,
       bufferFillPolicy = null;

  /// Requests a Perfetto system trace for [duration].
  const ProfilingRequest.systemTrace({
    this.tag,
    this.duration,
    this.bufferSizeKb,
    this.bufferFillPolicy,
  }) : type = ProfilingType.systemTrace,
       samplingFrequencyHz = null,
       samplingIntervalBytes = null,
       trackJavaAllocations = null;

  /// The kind of profile this request records.
  final ProfilingType type;

  /// Lowercased (first 20 alphanumeric characters and dashes) into the file name.
  final String? tag;

  /// How long to record; not used by [ProfilingRequest.javaHeapDump].
  final Duration? duration;

  /// Size of the recording buffer in kilobytes.
  final int? bufferSizeKb;

  /// Stack sampling: how many samples to take per second.
  final int? samplingFrequencyHz;

  /// Heap profile: average number of allocated bytes between samples.
  final int? samplingIntervalBytes;

  /// Heap profile: track Java allocations instead of native ones.
  final bool? trackJavaAllocations;

  /// System trace: what to do when the buffer fills up.
  final BufferFillPolicy? bufferFillPolicy;
}

/// `ProfilingResult.ERROR_*`, plus [unsupported] for devices without
/// ProfilingManager (below Android 15).
enum ProfilingError {
  /// No error: the profile was recorded.
  none(0),

  /// Denied by the system-wide rate limiter.
  rateLimitSystem(1),

  /// Denied by the per-app rate limiter.
  rateLimitProcess(2),

  /// Another profiling session is already running.
  profilingInProgress(3),

  /// Profiling failed while it was running.
  failedExecuting(4),

  /// The profile was recorded but post-processing it failed.
  failedPostProcessing(5),

  /// Not enough disk space to store the result.
  noDiskSpace(6),

  /// The request had invalid parameters.
  invalidRequest(7),

  /// An unspecified error, or a code this plugin does not know.
  unknown(8),

  /// ProfilingManager is not available on this device or platform.
  unsupported(-1);

  const ProfilingError(this.code);

  /// The raw `ProfilingResult.ERROR_*` value, or -1 for [unsupported].
  final int code;

  /// The error with [code], or [unknown] when no value matches.
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

  /// The raw `ProfilingTrigger.TRIGGER_TYPE_*` value, or -1 for [unknown].
  final int code;

  /// Minimum `Build.VERSION.SDK_INT`.
  final int minSdk;

  /// Minimum minor SDK version on top of [minSdk] (Android 16 QPR2 is 36.1).
  final int minSdkMinor;

  /// `Build.VERSION.SDK_INT_FULL` this trigger needs.
  int get minSdkFull => minSdk * 100000 + minSdkMinor;

  /// The trigger type with [code], or [unknown] when no value matches.
  static ProfilingTriggerType fromCode(int code) {
    for (final type in values) {
      if (type.code == code) return type;
    }
    return unknown;
  }
}

/// A trigger to register with `addProfilingTriggers`.
class ProfilingTrigger {
  /// Creates a trigger of [type] with an optional per-trigger rate limit.
  const ProfilingTrigger(this.type, {this.rateLimitingPeriodHours});

  /// The system event that captures the profile.
  final ProfilingTriggerType type;

  /// At most one result per this many hours for this trigger (the system
  /// also applies its own limits).
  final int? rateLimitingPeriodHours;
}

/// Outcome of a profiling request or a trigger.
class ProfilingResult {
  /// Creates a result; normally built by the plugin from the platform's answer.
  const ProfilingResult({
    required this.errorCode,
    this.errorMessage,
    this.filePath,
    this.tag,
    this.triggerCode = 0,
  });

  /// Raw `ProfilingResult.getErrorCode()`, -1 when unsupported.
  final int errorCode;

  /// The system's description of the failure, if any.
  final String? errorMessage;

  /// Absolute path of the trace in the app's files dir when [isSuccess].
  /// Open it in https://ui.perfetto.dev.
  final String? filePath;

  /// The tag of the request that produced this result.
  final String? tag;

  /// Raw `ProfilingResult.getTriggerType()`.
  final int triggerCode;

  /// [errorCode] as a [ProfilingError].
  ProfilingError get error => ProfilingError.fromCode(errorCode);

  /// [triggerCode] as a [ProfilingTriggerType]; [ProfilingTriggerType.none]
  /// for results of a [ProfilingRequest].
  ProfilingTriggerType get trigger =>
      ProfilingTriggerType.fromCode(triggerCode);

  /// Whether the profile was recorded and a [filePath] is available.
  bool get isSuccess => errorCode == 0 && filePath != null;

  @override
  String toString() => isSuccess
      ? 'ProfilingResult(ok, $filePath, trigger: ${trigger.name})'
      : 'ProfilingResult(${error.name}, $errorMessage)';
}

/// A running profiling request.
class ProfilingSession {
  /// Creates a session; use `AndroidDiagnostics.startProfiling` instead.
  ProfilingSession(this.id, this.request, this.result, this._stop);

  /// Unique identifier of this request within the app process.
  final String id;

  /// The request this session was started with.
  final ProfilingRequest request;

  /// Completes when the system delivers the result (after [stop], the
  /// duration or the system timeout).
  final Future<ProfilingResult> result;
  final Future<bool> Function() _stop;

  /// Ends a continuous profile early; the result still arrives in [result].
  /// Returns false when the request has already finished.
  Future<bool> stop() => _stop();
}
