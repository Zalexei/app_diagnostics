import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// What MetricKit offers on the current iOS device.
@immutable
class MetricKitSupport {
  const MetricKitSupport({
    required this.systemVersion,
    required this.isSimulator,
    required this.diagnostics,
    required this.immediateDelivery,
    required this.appLaunchDiagnostics,
    required this.extendedMetadata,
  });

  /// Answer outside iOS.
  static const none = MetricKitSupport(
    systemVersion: '',
    isSimulator: false,
    diagnostics: false,
    immediateDelivery: false,
    appLaunchDiagnostics: false,
    extendedMetadata: false,
  );

  /// iOS version, e.g. `18.2`; empty outside iOS.
  final String systemVersion;

  /// The simulator never receives MetricKit reports.
  final bool isSimulator;

  /// Diagnostic reports and exit counts (iOS 14).
  final bool diagnostics;

  /// Diagnostics arrive on the next launch instead of once a day (iOS 15).
  final bool immediateDelivery;

  /// [AppLaunchDiagnostic] (iOS 16).
  final bool appLaunchDiagnostics;

  /// [MetricKitMetadata.pid], [CrashDiagnostic.exceptionReason] and the
  /// process state summary of crashed processes (iOS 17).
  final bool extendedMetadata;

  @override
  String toString() =>
      'MetricKitSupport(iOS $systemVersion, simulator: $isSimulator, '
      'diagnostics: $diagnostics, immediateDelivery: $immediateDelivery, '
      'appLaunchDiagnostics: $appLaunchDiagnostics, '
      'extendedMetadata: $extendedMetadata)';
}

/// The two kinds of MetricKit reports.
enum MetricKitReportKind {
  /// [MetricKitDiagnosticReport]: crashes, hangs, CPU and disk exceptions.
  diagnostic(0),

  /// [MetricKitMetricReport]: daily metrics, including exit counts.
  metric(1);

  const MetricKitReportKind(this.code);

  final int code;

  static MetricKitReportKind? fromCode(int code) {
    for (final k in values) {
      if (k.code == code) return k;
    }
    return null;
  }
}

/// Device and app details MetricKit attaches to a report (MXMetaData).
@immutable
class MetricKitMetadata {
  const MetricKitMetadata({
    this.appVersion,
    this.appBuildVersion,
    this.osVersion,
    this.deviceType,
    this.platformArchitecture,
    this.regionFormat,
    this.pid,
    this.isTestFlightApp,
    this.lowPowerModeEnabled,
    this.bundleIdentifier,
  });

  factory MetricKitMetadata.fromJson(Map<String, Object?> json) =>
      MetricKitMetadata(
        appVersion: json['appVersion'] as String?,
        appBuildVersion: json['appBuildVersion'] as String?,
        osVersion: json['osVersion'] as String?,
        deviceType: json['deviceType'] as String?,
        platformArchitecture: json['platformArchitecture'] as String?,
        regionFormat: json['regionFormat'] as String?,
        pid: _intOrNull(json['pid']),
        isTestFlightApp: json['isTestFlightApp'] as bool?,
        lowPowerModeEnabled: json['lowPowerModeEnabled'] as bool?,
        bundleIdentifier: json['bundleIdentifier'] as String?,
      );

  /// CFBundleShortVersionString of the app that produced the report.
  final String? appVersion;
  final String? appBuildVersion;

  /// For example `iPhone OS 18.2 (22C152)`.
  final String? osVersion;

  /// Hardware model, for example `iPhone17,1`.
  final String? deviceType;
  final String? platformArchitecture;
  final String? regionFormat;

  /// iOS 17+.
  final int? pid;

  /// iOS 17+.
  final bool? isTestFlightApp;

  /// iOS 17+.
  final bool? lowPowerModeEnabled;

  /// iOS 26+.
  final String? bundleIdentifier;

  Map<String, Object?> toJson() => {
    'appVersion': appVersion,
    'appBuildVersion': appBuildVersion,
    'osVersion': osVersion,
    'deviceType': deviceType,
    'platformArchitecture': platformArchitecture,
    'regionFormat': regionFormat,
    'pid': pid,
    'isTestFlightApp': isTestFlightApp,
    'lowPowerModeEnabled': lowPowerModeEnabled,
    'bundleIdentifier': bundleIdentifier,
  }..removeWhere((_, v) => v == null);
}

/// One frame of a MetricKit call stack. Addresses are unsymbolicated:
/// symbolicate with the dSYM of [binaryUuid] (`atos -o App.dSYM -l <load
/// address> <address>`), or with `flutter symbolize` for Dart frames of an
/// app built with `--split-debug-info`.
@immutable
class CallStackFrame {
  const CallStackFrame({
    required this.binaryName,
    required this.binaryUuid,
    required this.address,
    required this.offsetIntoBinaryTextSegment,
    required this.sampleCount,
    this.subFrames = const [],
  });

  factory CallStackFrame.fromJson(Map<String, Object?> json) => CallStackFrame(
    binaryName: json['binaryName'] as String? ?? '???',
    binaryUuid: json['binaryUUID'] as String? ?? '',
    address: _intOrNull(json['address']) ?? 0,
    offsetIntoBinaryTextSegment:
        _intOrNull(json['offsetIntoBinaryTextSegment']) ?? 0,
    sampleCount: _intOrNull(json['sampleCount']) ?? 0,
    subFrames: [
      for (final f in json['subFrames'] as List? ?? const [])
        CallStackFrame.fromJson((f as Map).cast<String, Object?>()),
    ],
  );

  final String binaryName;
  final String binaryUuid;
  final int address;
  final int offsetIntoBinaryTextSegment;

  /// How many samples hit this frame (sampled trees of CPU and disk write
  /// exceptions); 1 for crash stacks.
  final int sampleCount;
  final List<CallStackFrame> subFrames;

  /// `index  binary  0xaddress  binary + offset`, the layout of an Apple
  /// crash report.
  String format(int index) =>
      '${'$index'.padRight(4)}${binaryName.padRight(28)} '
      '0x${address.toRadixString(16).padLeft(16, '0')} '
      '$binaryName + $offsetIntoBinaryTextSegment';
}

/// One stack of a [CallStackTree]: a thread of a crash or a hang, or a
/// sampled tree of a CPU or disk write exception.
@immutable
class CallStack {
  const CallStack({required this.threadAttributed, required this.rootFrames});

  factory CallStack.fromJson(Map<String, Object?> json) => CallStack(
    threadAttributed: json['threadAttributed'] as bool? ?? false,
    rootFrames: [
      for (final f in json['callStackRootFrames'] as List? ?? const [])
        CallStackFrame.fromJson((f as Map).cast<String, Object?>()),
    ],
  );

  /// The thread MetricKit blames: the crashed or the hung one.
  final bool threadAttributed;
  final List<CallStackFrame> rootFrames;

  /// The frames of a thread stack in MetricKit's order (frame 0 first), each
  /// frame being the only sub-frame of the previous one.
  List<CallStackFrame> get frames {
    final out = <CallStackFrame>[];
    var level = rootFrames;
    while (level.isNotEmpty) {
      out.add(level.first);
      level = level.first.subFrames;
    }
    return out;
  }
}

/// MXCallStackTree: per-thread stacks of crashes and hangs, or a sampled
/// tree of CPU and disk write exceptions.
@immutable
class CallStackTree {
  const CallStackTree({
    required this.callStackPerThread,
    required this.callStacks,
  });

  factory CallStackTree.fromJson(Map<String, Object?> json) => CallStackTree(
    callStackPerThread: json['callStackPerThread'] as bool? ?? false,
    callStacks: [
      for (final s in json['callStacks'] as List? ?? const [])
        CallStack.fromJson((s as Map).cast<String, Object?>()),
    ],
  );

  static const empty = CallStackTree(callStackPerThread: true, callStacks: []);

  /// True for crashes and hangs (one stack per thread), false for sampled
  /// trees.
  final bool callStackPerThread;
  final List<CallStack> callStacks;

  CallStack? get attributedStack {
    for (final s in callStacks) {
      if (s.threadAttributed) return s;
    }
    return null;
  }

  /// Text in the layout of an Apple crash report (per-thread stacks) or an
  /// indented tree with sample counts (sampled trees).
  String toText() {
    final b = StringBuffer();
    for (var i = 0; i < callStacks.length; i++) {
      final stack = callStacks[i];
      if (callStackPerThread) {
        b.writeln('Thread $i${stack.threadAttributed ? ' (attributed)' : ''}:');
        final frames = stack.frames;
        for (var j = 0; j < frames.length; j++) {
          b.writeln(frames[j].format(j));
        }
      } else {
        b.writeln('Call stack $i:');
        _writeTree(b, stack.rootFrames, 0);
      }
      b.writeln();
    }
    return b.toString().trimRight();
  }

  static void _writeTree(
    StringBuffer b,
    List<CallStackFrame> frames,
    int depth,
  ) {
    for (final f in frames) {
      b.writeln(
        '${'  ' * depth}[${f.sampleCount}] ${f.binaryName} + '
        '${f.offsetIntoBinaryTextSegment} '
        '(0x${f.address.toRadixString(16)})',
      );
      _writeTree(b, f.subFrames, depth + 1);
    }
  }
}

/// Details of an uncaught Objective-C exception (iOS 17+).
@immutable
class ObjCExceptionReason {
  const ObjCExceptionReason({
    required this.composedMessage,
    required this.formatString,
    required this.arguments,
    required this.exceptionType,
    required this.className,
    required this.exceptionName,
  });

  factory ObjCExceptionReason.fromJson(Map<String, Object?> json) =>
      ObjCExceptionReason(
        composedMessage: json['composedMessage'] as String? ?? '',
        formatString: json['formatString'] as String? ?? '',
        arguments: [
          for (final a in json['arguments'] as List? ?? const []) '$a',
        ],
        exceptionType: json['exceptionType'] as String? ?? '',
        className: json['className'] as String? ?? '',
        exceptionName: json['exceptionName'] as String? ?? '',
      );

  /// The exception reason with its arguments filled in.
  final String composedMessage;
  final String formatString;
  final List<String> arguments;
  final String exceptionType;

  /// Class of the exception object, for example `NSException`.
  final String className;

  /// For example `NSInvalidArgumentException`.
  final String exceptionName;
}

/// A MetricKit diagnostic: [CrashDiagnostic], [HangDiagnostic],
/// [CpuExceptionDiagnostic], [DiskWriteExceptionDiagnostic] or
/// [AppLaunchDiagnostic].
@immutable
sealed class MetricKitDiagnostic {
  const MetricKitDiagnostic({
    required this.metadata,
    required this.callStackTree,
    this.processStateSummary,
  });

  final MetricKitMetadata metadata;
  final CallStackTree callStackTree;

  /// What the process stored with `IosDiagnostics.setProcessStateSummary`,
  /// matched by [MetricKitMetadata.pid] (iOS 17+); null otherwise.
  final Uint8List? processStateSummary;

  String? get processStateSummaryText {
    final s = processStateSummary;
    return s == null ? null : utf8.decode(s, allowMalformed: true);
  }

  /// One-line description, for example `crash EXC_BAD_ACCESS (SIGSEGV)`.
  String get title;
}

/// MXCrashDiagnostic.
final class CrashDiagnostic extends MetricKitDiagnostic {
  const CrashDiagnostic({
    required super.metadata,
    required super.callStackTree,
    super.processStateSummary,
    this.exceptionType,
    this.exceptionCode,
    this.signal,
    this.terminationReason,
    this.virtualMemoryRegionInfo,
    this.exceptionReason,
  });

  /// Mach exception type, see [exceptionTypeName].
  final int? exceptionType;
  final int? exceptionCode;

  /// Darwin signal number, see [signalName].
  final int? signal;

  /// For example `Namespace SIGNAL, Code 0xb`.
  final String? terminationReason;

  /// Memory region of a bad access.
  final String? virtualMemoryRegionInfo;

  /// The uncaught Objective-C exception (iOS 17+).
  final ObjCExceptionReason? exceptionReason;

  /// For example `EXC_BAD_ACCESS`; null for unknown types.
  String? get exceptionTypeName => _machExceptions[exceptionType];

  /// For example `SIGSEGV`; null for unknown signals.
  String? get signalName => _darwinSignals[signal];

  @override
  String get title {
    final parts = [
      'crash',
      exceptionTypeName ??
          (exceptionType == null ? null : 'exception $exceptionType'),
      if (signal != null) '(${signalName ?? 'signal $signal'})',
      if (exceptionReason != null) exceptionReason!.exceptionName,
    ];
    return parts.whereType<String>().join(' ');
  }
}

/// MXHangDiagnostic: the main thread did not respond to input.
final class HangDiagnostic extends MetricKitDiagnostic {
  const HangDiagnostic({
    required super.metadata,
    required super.callStackTree,
    super.processStateSummary,
    required this.hangDuration,
  });

  final Duration hangDuration;

  @override
  String get title => 'hang ${_seconds(hangDuration)}';
}

/// MXCPUExceptionDiagnostic: too much CPU time in a short period.
final class CpuExceptionDiagnostic extends MetricKitDiagnostic {
  const CpuExceptionDiagnostic({
    required super.metadata,
    required super.callStackTree,
    super.processStateSummary,
    required this.totalCpuTime,
    required this.totalSampledTime,
  });

  final Duration totalCpuTime;
  final Duration totalSampledTime;

  @override
  String get title =>
      'CPU exception ${_seconds(totalCpuTime)} in ${_seconds(totalSampledTime)}';
}

/// MXDiskWriteExceptionDiagnostic: too much data written to disk.
final class DiskWriteExceptionDiagnostic extends MetricKitDiagnostic {
  const DiskWriteExceptionDiagnostic({
    required super.metadata,
    required super.callStackTree,
    super.processStateSummary,
    required this.totalWritesBytes,
  });

  final int totalWritesBytes;

  @override
  String get title =>
      'disk writes ${(totalWritesBytes / (1 << 20)).toStringAsFixed(1)} MB';
}

/// MXAppLaunchDiagnostic: a slow launch (iOS 16+).
final class AppLaunchDiagnostic extends MetricKitDiagnostic {
  const AppLaunchDiagnostic({
    required super.metadata,
    required super.callStackTree,
    super.processStateSummary,
    required this.launchDuration,
  });

  final Duration launchDuration;

  @override
  String get title => 'slow launch ${_seconds(launchDuration)}';
}

/// One MXDiagnosticPayload: the diagnostics MetricKit delivered at once.
@immutable
class MetricKitDiagnosticReport {
  const MetricKitDiagnosticReport({
    required this.begin,
    required this.end,
    required this.receivedAt,
    this.crashes = const [],
    this.hangs = const [],
    this.cpuExceptions = const [],
    this.diskWriteExceptions = const [],
    this.appLaunches = const [],
    this.raw = const {},
  });

  /// Parses a report stored by the iOS side of the plugin.
  ///
  /// Throws [FormatException] for malformed input.
  factory MetricKitDiagnosticReport.fromJson(String json) {
    final m = _decodeObject(json);
    try {
      List<T> list<T>(String key, T Function(Map<String, Object?> m) parse) => [
        for (final e in m[key] as List? ?? const [])
          parse((e as Map).cast<String, Object?>()),
      ];
      return MetricKitDiagnosticReport(
        begin: _time(m['begin']),
        end: _time(m['end']),
        receivedAt: _time(m['receivedAt']),
        crashes: list('crashes', (d) {
          final reason = d['exceptionReason'] as Map?;
          return CrashDiagnostic(
            metadata: _meta(d),
            callStackTree: _tree(d),
            processStateSummary: _summary(d),
            exceptionType: _intOrNull(d['exceptionType']),
            exceptionCode: _intOrNull(d['exceptionCode']),
            signal: _intOrNull(d['signal']),
            terminationReason: d['terminationReason'] as String?,
            virtualMemoryRegionInfo: d['virtualMemoryRegionInfo'] as String?,
            exceptionReason: reason == null
                ? null
                : ObjCExceptionReason.fromJson(reason.cast<String, Object?>()),
          );
        }),
        hangs: list(
          'hangs',
          (d) => HangDiagnostic(
            metadata: _meta(d),
            callStackTree: _tree(d),
            processStateSummary: _summary(d),
            hangDuration: _duration(d['hangDurationSec']),
          ),
        ),
        cpuExceptions: list(
          'cpuExceptions',
          (d) => CpuExceptionDiagnostic(
            metadata: _meta(d),
            callStackTree: _tree(d),
            processStateSummary: _summary(d),
            totalCpuTime: _duration(d['totalCpuTimeSec']),
            totalSampledTime: _duration(d['totalSampledTimeSec']),
          ),
        ),
        diskWriteExceptions: list(
          'diskWriteExceptions',
          (d) => DiskWriteExceptionDiagnostic(
            metadata: _meta(d),
            callStackTree: _tree(d),
            processStateSummary: _summary(d),
            totalWritesBytes: (d['totalWritesBytes'] as num? ?? 0).round(),
          ),
        ),
        appLaunches: list(
          'appLaunches',
          (d) => AppLaunchDiagnostic(
            metadata: _meta(d),
            callStackTree: _tree(d),
            processStateSummary: _summary(d),
            launchDuration: _duration(d['launchDurationSec']),
          ),
        ),
        raw: (m['raw'] as Map? ?? const {}).cast<String, Object?>(),
      );
    } on TypeError catch (e) {
      throw FormatException('Malformed MetricKit diagnostic report: $e');
    }
  }

  /// MXDiagnosticPayload.timeStampBegin / timeStampEnd.
  final DateTime begin;
  final DateTime end;

  /// When the plugin stored the report.
  final DateTime receivedAt;

  final List<CrashDiagnostic> crashes;
  final List<HangDiagnostic> hangs;
  final List<CpuExceptionDiagnostic> cpuExceptions;
  final List<DiskWriteExceptionDiagnostic> diskWriteExceptions;
  final List<AppLaunchDiagnostic> appLaunches;

  /// MetricKit's own jsonRepresentation(), for uploading as is.
  final Map<String, Object?> raw;

  /// Every diagnostic of the report, crashes first.
  List<MetricKitDiagnostic> get diagnostics => [
    ...crashes,
    ...hangs,
    ...cpuExceptions,
    ...diskWriteExceptions,
    ...appLaunches,
  ];

  String get rawJson => jsonEncode(raw);
}

/// Exit counts of one day (MXForegroundExitData / MXBackgroundExitData).
/// The foreground has no memory pressure, CPU limit, locked file and task
/// assertion exits: those fields stay 0.
@immutable
class AppExitCounts {
  const AppExitCounts({
    this.normal = 0,
    this.abnormal = 0,
    this.watchdog = 0,
    this.memoryResourceLimit = 0,
    this.badAccess = 0,
    this.illegalInstruction = 0,
    this.memoryPressure = 0,
    this.cpuResourceLimit = 0,
    this.suspendedWithLockedFile = 0,
    this.backgroundTaskAssertionTimeout = 0,
  });

  factory AppExitCounts.fromJson(Map<String, Object?> json) {
    int c(String key) => _intOrNull(json[key]) ?? 0;
    return AppExitCounts(
      normal: c('normal'),
      abnormal: c('abnormal'),
      watchdog: c('watchdog'),
      memoryResourceLimit: c('memoryResourceLimit'),
      badAccess: c('badAccess'),
      illegalInstruction: c('illegalInstruction'),
      memoryPressure: c('memoryPressure'),
      cpuResourceLimit: c('cpuResourceLimit'),
      suspendedWithLockedFile: c('suspendedWithLockedFile'),
      backgroundTaskAssertionTimeout: c('backgroundTaskAssertionTimeout'),
    );
  }

  /// The app quit by itself or the user closed it.
  final int normal;

  /// Crashes other than bad access and illegal instruction (abort, uncaught
  /// exceptions, ...).
  final int abnormal;

  /// Killed by the watchdog: launch, resume or a hang took too long.
  final int watchdog;

  /// Killed for using more memory than the device allows (OOM).
  final int memoryResourceLimit;

  /// SIGSEGV / SIGBUS.
  final int badAccess;

  /// SIGILL.
  final int illegalInstruction;

  /// Background only: the system freed memory for other apps.
  final int memoryPressure;

  /// Background only: too much CPU in the background.
  final int cpuResourceLimit;

  /// Background only: suspended while holding a file lock.
  final int suspendedWithLockedFile;

  /// Background only: a background task ran out of time.
  final int backgroundTaskAssertionTimeout;

  /// Exits caused by the app: everything except [normal] and
  /// [memoryPressure].
  int get problems =>
      abnormal +
      watchdog +
      memoryResourceLimit +
      badAccess +
      illegalInstruction +
      cpuResourceLimit +
      suspendedWithLockedFile +
      backgroundTaskAssertionTimeout;

  int get total => normal + memoryPressure + problems;

  Map<String, int> toJson() => {
    'normal': normal,
    'abnormal': abnormal,
    'watchdog': watchdog,
    'memoryResourceLimit': memoryResourceLimit,
    'badAccess': badAccess,
    'illegalInstruction': illegalInstruction,
    'memoryPressure': memoryPressure,
    'cpuResourceLimit': cpuResourceLimit,
    'suspendedWithLockedFile': suspendedWithLockedFile,
    'backgroundTaskAssertionTimeout': backgroundTaskAssertionTimeout,
  };
}

/// One MXMetricPayload: a day of metrics. The parsed part covers exits and
/// peak memory; [raw] has everything else (launch times, hang rate, ...).
@immutable
class MetricKitMetricReport {
  const MetricKitMetricReport({
    required this.begin,
    required this.end,
    required this.receivedAt,
    this.appVersion,
    this.multipleAppVersions = false,
    this.metadata,
    this.foregroundExits,
    this.backgroundExits,
    this.peakMemoryBytes,
    this.raw = const {},
  });

  /// Parses a report stored by the iOS side of the plugin.
  ///
  /// Throws [FormatException] for malformed input.
  factory MetricKitMetricReport.fromJson(String json) {
    final m = _decodeObject(json);
    try {
      final meta = m['meta'] as Map?;
      final fg = m['foregroundExits'] as Map?;
      final bg = m['backgroundExits'] as Map?;
      return MetricKitMetricReport(
        begin: _time(m['begin']),
        end: _time(m['end']),
        receivedAt: _time(m['receivedAt']),
        appVersion: m['appVersion'] as String?,
        multipleAppVersions: m['multipleAppVersions'] as bool? ?? false,
        metadata: meta == null
            ? null
            : MetricKitMetadata.fromJson(meta.cast<String, Object?>()),
        foregroundExits: fg == null
            ? null
            : AppExitCounts.fromJson(fg.cast<String, Object?>()),
        backgroundExits: bg == null
            ? null
            : AppExitCounts.fromJson(bg.cast<String, Object?>()),
        peakMemoryBytes: (m['peakMemoryBytes'] as num?)?.round(),
        raw: (m['raw'] as Map? ?? const {}).cast<String, Object?>(),
      );
    } on TypeError catch (e) {
      throw FormatException('Malformed MetricKit metric report: $e');
    }
  }

  final DateTime begin;
  final DateTime end;
  final DateTime receivedAt;

  /// The latest app version in the period.
  final String? appVersion;

  /// The period covers more than one app version.
  final bool multipleAppVersions;
  final MetricKitMetadata? metadata;

  /// Null when the report has no exit metrics (before iOS 14).
  final AppExitCounts? foregroundExits;
  final AppExitCounts? backgroundExits;
  final int? peakMemoryBytes;

  /// MetricKit's own jsonRepresentation().
  final Map<String, Object?> raw;

  String get rawJson => jsonEncode(raw);
}

Map<String, Object?> _decodeObject(String json) {
  final decoded = jsonDecode(json);
  if (decoded is! Map) {
    throw const FormatException('A MetricKit report must be a JSON object');
  }
  return decoded.cast<String, Object?>();
}

int? _intOrNull(Object? v) => v is num ? v.toInt() : null;

DateTime _time(Object? ms) =>
    DateTime.fromMillisecondsSinceEpoch(_intOrNull(ms) ?? 0);

Duration _duration(Object? seconds) =>
    Duration(microseconds: ((seconds as num? ?? 0) * 1e6).round());

MetricKitMetadata _meta(Map<String, Object?> d) =>
    MetricKitMetadata.fromJson((d['meta'] as Map? ?? const {}).cast());

CallStackTree _tree(Map<String, Object?> d) {
  final t = d['callStackTree'] as Map?;
  return t == null
      ? CallStackTree.empty
      : CallStackTree.fromJson(t.cast<String, Object?>());
}

Uint8List? _summary(Map<String, Object?> d) {
  final s = d['processStateSummary'] as String?;
  return s == null ? null : base64Decode(s);
}

String _seconds(Duration d) =>
    '${(d.inMicroseconds / 1e6).toStringAsFixed(d.inSeconds >= 10 ? 0 : 1)} s';

// mach/exception_types.h
const _machExceptions = {
  1: 'EXC_BAD_ACCESS',
  2: 'EXC_BAD_INSTRUCTION',
  3: 'EXC_ARITHMETIC',
  4: 'EXC_EMULATION',
  5: 'EXC_SOFTWARE',
  6: 'EXC_BREAKPOINT',
  7: 'EXC_SYSCALL',
  8: 'EXC_MACH_SYSCALL',
  9: 'EXC_RPC_ALERT',
  10: 'EXC_CRASH',
  11: 'EXC_RESOURCE',
  12: 'EXC_GUARD',
  13: 'EXC_CORPSE_NOTIFY',
};

// sys/signal.h (Darwin numbering).
const _darwinSignals = {
  1: 'SIGHUP',
  2: 'SIGINT',
  3: 'SIGQUIT',
  4: 'SIGILL',
  5: 'SIGTRAP',
  6: 'SIGABRT',
  7: 'SIGEMT',
  8: 'SIGFPE',
  9: 'SIGKILL',
  10: 'SIGBUS',
  11: 'SIGSEGV',
  12: 'SIGSYS',
  13: 'SIGPIPE',
  14: 'SIGALRM',
  15: 'SIGTERM',
};
