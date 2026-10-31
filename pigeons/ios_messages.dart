// Pigeon schema for the Dart <-> Swift bridge (MetricKit).
// Regenerate with: dart run pigeon --input pigeons/ios_messages.dart
//
// Reports travel as JSON strings written by the Swift side when MetricKit
// delivers them; the Dart layer parses them (see lib/src/metrickit.dart), so
// the stored format and its parser are tested together on the Dart side.
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/ios_messages.g.dart',
    swiftOut: 'ios/app_diagnostics/Sources/app_diagnostics/IosMessages.g.swift',
    dartPackageName: 'app_diagnostics',
  ),
)
/// What the current device supports. Computed from the iOS version.
class IosSupportMessage {
  IosSupportMessage({
    required this.systemVersion,
    required this.isSimulator,
    required this.diagnostics,
    required this.immediateDelivery,
    required this.appLaunchDiagnostics,
    required this.extendedMetadata,
  });

  /// UIDevice.systemVersion, e.g. "18.2".
  String systemVersion;
  bool isSimulator;

  /// MXDiagnosticPayload and MXAppExitMetric (iOS 14).
  bool diagnostics;

  /// Diagnostics arrive on the next launch instead of once a day (iOS 15).
  bool immediateDelivery;

  /// MXAppLaunchDiagnostic (iOS 16).
  bool appLaunchDiagnostics;

  /// pid, Objective-C exception reason and other metadata (iOS 17).
  bool extendedMetadata;
}

@HostApi()
abstract class IosDiagnosticsHostApi {
  IosSupportMessage getSupport();

  /// Stored reports of [kind] (0 = diagnostics, 1 = daily metrics) as JSON,
  /// oldest first.
  @TaskQueue(type: TaskQueueType.serialBackgroundThread)
  List<String> getReports(int kind);

  /// Like [getReports], but only reports not returned by an earlier call;
  /// the marker is persisted.
  @TaskQueue(type: TaskQueueType.serialBackgroundThread)
  List<String> takeNewReports(int kind);

  @TaskQueue(type: TaskQueueType.serialBackgroundThread)
  void clearReports();

  /// Stores [summary] for the current process; it is attached to diagnostics
  /// that MetricKit later reports for this pid (iOS 17+). Null clears it.
  @TaskQueue(type: TaskQueueType.serialBackgroundThread)
  bool setProcessStateSummary(Uint8List? summary);
}

@EventChannelApi()
abstract class IosDiagnosticsEventApi {
  /// The kind (0 = diagnostics, 1 = metrics) of every report stored while
  /// Dart listens.
  int reportsArrived();
}
