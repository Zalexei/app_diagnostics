import 'dart:convert';
import 'dart:typed_data';

import 'ios_platform.dart';
import 'metrickit.dart';

/// iOS crash, hang and exit reports from MetricKit. Every call is safe on
/// any platform: outside iOS it returns empty results.
///
/// MetricKit delivers each report once, often before Dart runs; the plugin
/// subscribes when the app starts and keeps reports on disk (the latest 50
/// diagnostic and 30 metric reports) until you read them.
abstract final class IosDiagnostics {
  static IosDiagnosticsPlatform get _platform =>
      IosDiagnosticsPlatform.instance;

  /// Same limit as Android's process state summary, so one call fits both.
  static const int maxProcessStateSummaryBytes = 128;

  /// What MetricKit offers on this device.
  static Future<MetricKitSupport> getSupport() => _platform.getSupport();

  /// Stored diagnostic reports (crashes, hangs, CPU and disk write
  /// exceptions, slow launches), newest first.
  static Future<List<MetricKitDiagnosticReport>> getDiagnosticReports() =>
      _platform.getDiagnosticReports(onlyNew: false);

  /// Diagnostic reports stored since the previous call, newest first. The
  /// marker is persisted, so each report is returned once across launches.
  static Future<List<MetricKitDiagnosticReport>> takeNewDiagnosticReports() =>
      _platform.getDiagnosticReports(onlyNew: true);

  /// Stored daily metric reports (exit counts, peak memory, ...), newest
  /// first.
  static Future<List<MetricKitMetricReport>> getMetricReports() =>
      _platform.getMetricReports(onlyNew: false);

  /// Daily metric reports stored since the previous call, newest first.
  static Future<List<MetricKitMetricReport>> takeNewMetricReports() =>
      _platform.getMetricReports(onlyNew: true);

  /// Deletes every stored report.
  static Future<void> clearReports() => _platform.clearReports();

  /// Up to [maxProcessStateSummaryBytes] bytes about what the process is
  /// doing. When MetricKit later reports a crash or hang of this process, the
  /// summary comes back in [MetricKitDiagnostic.processStateSummary]
  /// (matched by pid, iOS 17+). Null clears it. Returns false outside iOS.
  ///
  /// Throws [ArgumentError] when [summary] is longer than the limit.
  static Future<bool> setProcessStateSummary(Uint8List? summary) {
    if (summary != null && summary.length > maxProcessStateSummaryBytes) {
      throw ArgumentError.value(
        summary.length,
        'summary',
        'at most $maxProcessStateSummaryBytes bytes',
      );
    }
    return _platform.setProcessStateSummary(summary);
  }

  /// [setProcessStateSummary] with UTF-8 text.
  static Future<bool> setProcessStateSummaryText(String text) =>
      setProcessStateSummary(Uint8List.fromList(utf8.encode(text)));

  /// Fires when the plugin stores a new report while the app runs (on iOS
  /// 15+ diagnostics usually arrive a few seconds after launch). Call the
  /// matching `takeNew...` method to read it.
  static Stream<MetricKitReportKind> get reportsArrived =>
      _platform.reportsArrived;
}
