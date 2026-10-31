import 'package:flutter/foundation.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'ios_messages.g.dart';
import 'ios_messages.g.dart' as generated show reportsArrived;
import 'metrickit.dart';

/// The platform layer behind `IosDiagnostics`. Replace
/// [IosDiagnosticsPlatform.instance] with a fake in your own tests.
abstract class IosDiagnosticsPlatform extends PlatformInterface {
  IosDiagnosticsPlatform() : super(token: _token);

  static final Object _token = Object();

  static IosDiagnosticsPlatform _instance =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
      ? PigeonIosDiagnostics()
      : UnsupportedIosDiagnostics();

  static IosDiagnosticsPlatform get instance => _instance;

  static set instance(IosDiagnosticsPlatform instance) {
    PlatformInterface.verify(instance, _token);
    _instance = instance;
  }

  Future<MetricKitSupport> getSupport();

  /// Stored reports, newest first; with [onlyNew] only the ones no earlier
  /// call returned.
  Future<List<MetricKitDiagnosticReport>> getDiagnosticReports({
    required bool onlyNew,
  });

  Future<List<MetricKitMetricReport>> getMetricReports({required bool onlyNew});

  Future<void> clearReports();

  Future<bool> setProcessStateSummary(Uint8List? summary);

  Stream<MetricKitReportKind> get reportsArrived;
}

/// Talks to the Swift side through Pigeon.
class PigeonIosDiagnostics extends IosDiagnosticsPlatform {
  PigeonIosDiagnostics({IosDiagnosticsHostApi? api, Stream<int>? arrivals})
    : _api = api ?? IosDiagnosticsHostApi(),
      _arrivals = arrivals;

  final IosDiagnosticsHostApi _api;
  final Stream<int>? _arrivals;

  @override
  Future<MetricKitSupport> getSupport() async {
    final m = await _api.getSupport();
    return MetricKitSupport(
      systemVersion: m.systemVersion,
      isSimulator: m.isSimulator,
      diagnostics: m.diagnostics,
      immediateDelivery: m.immediateDelivery,
      appLaunchDiagnostics: m.appLaunchDiagnostics,
      extendedMetadata: m.extendedMetadata,
    );
  }

  @override
  Future<List<MetricKitDiagnosticReport>> getDiagnosticReports({
    required bool onlyNew,
  }) async => _parse(
    await _fetch(MetricKitReportKind.diagnostic, onlyNew),
    MetricKitDiagnosticReport.fromJson,
  );

  @override
  Future<List<MetricKitMetricReport>> getMetricReports({
    required bool onlyNew,
  }) async => _parse(
    await _fetch(MetricKitReportKind.metric, onlyNew),
    MetricKitMetricReport.fromJson,
  );

  Future<List<String>> _fetch(MetricKitReportKind kind, bool onlyNew) =>
      onlyNew ? _api.takeNewReports(kind.code) : _api.getReports(kind.code);

  @override
  Future<void> clearReports() => _api.clearReports();

  @override
  Future<bool> setProcessStateSummary(Uint8List? summary) =>
      _api.setProcessStateSummary(summary);

  /// One stream for all listeners: every new EventChannel stream would take
  /// the channel over from the previous one.
  @override
  late final Stream<MetricKitReportKind> reportsArrived =
      (_arrivals ?? generated.reportsArrived())
          .map(MetricKitReportKind.fromCode)
          .where((k) => k != null)
          .cast<MetricKitReportKind>();

  /// Oldest-first JSON from the store to newest-first reports; a report that
  /// fails to parse is skipped rather than hiding the others.
  static List<T> _parse<T>(List<String> stored, T Function(String) parse) {
    final out = <T>[];
    for (final json in stored.reversed) {
      try {
        out.add(parse(json));
      } on FormatException catch (e) {
        debugPrint('app_diagnostics: skipping a MetricKit report: $e');
      }
    }
    return out;
  }
}

/// Used outside iOS: every call answers "nothing here".
class UnsupportedIosDiagnostics extends IosDiagnosticsPlatform {
  @override
  Future<MetricKitSupport> getSupport() async => MetricKitSupport.none;

  @override
  Future<List<MetricKitDiagnosticReport>> getDiagnosticReports({
    required bool onlyNew,
  }) async => const [];

  @override
  Future<List<MetricKitMetricReport>> getMetricReports({
    required bool onlyNew,
  }) async => const [];

  @override
  Future<void> clearReports() async {}

  @override
  Future<bool> setProcessStateSummary(Uint8List? summary) async => false;

  @override
  Stream<MetricKitReportKind> get reportsArrived => const Stream.empty();
}
