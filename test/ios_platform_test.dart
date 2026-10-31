import 'dart:async';
import 'dart:convert';

import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:app_diagnostics/src/ios_messages.g.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for the Swift side: keeps "stored" JSON per kind, oldest first.
class FakeIosHost extends IosDiagnosticsHostApi {
  final reports = <int, List<String>>{0: [], 1: []};
  final taken = <int, int>{0: 0, 1: 0};
  Uint8List? summary;
  bool cleared = false;

  @override
  Future<IosSupportMessage> getSupport() async => IosSupportMessage(
    systemVersion: '18.2',
    isSimulator: true,
    diagnostics: true,
    immediateDelivery: true,
    appLaunchDiagnostics: true,
    extendedMetadata: true,
  );

  @override
  Future<List<String>> getReports(int kind) async => [...reports[kind]!];

  @override
  Future<List<String>> takeNewReports(int kind) async {
    final all = reports[kind]!;
    final fresh = all.sublist(taken[kind]!);
    taken[kind] = all.length;
    return fresh;
  }

  @override
  Future<void> clearReports() async => cleared = true;

  @override
  Future<bool> setProcessStateSummary(Uint8List? summary) async {
    this.summary = summary;
    return true;
  }
}

String diagnostic(int receivedAt) => jsonEncode({
  'receivedAt': receivedAt,
  'hangs': [
    {'hangDurationSec': 1.0},
  ],
});

void main() {
  late FakeIosHost host;
  late StreamController<int> arrivals;

  setUp(() {
    host = FakeIosHost();
    arrivals = StreamController<int>.broadcast();
    IosDiagnosticsPlatform.instance = PigeonIosDiagnostics(
      api: host,
      arrivals: arrivals.stream,
    );
  });

  tearDown(() => arrivals.close());

  test('support flags survive the channel', () async {
    final s = await IosDiagnostics.getSupport();
    expect(s.systemVersion, '18.2');
    expect(s.isSimulator, isTrue);
    expect(s.extendedMetadata, isTrue);
  });

  test('reports come newest first and broken ones are skipped', () async {
    host.reports[0]!.addAll([
      diagnostic(1),
      '{"hangs": "oops"}',
      diagnostic(3),
    ]);
    final reports = await IosDiagnostics.getDiagnosticReports();
    expect(reports.map((r) => r.receivedAt.millisecondsSinceEpoch), [3, 1]);
  });

  test('takeNew returns each report once per kind', () async {
    host.reports[0]!.add(diagnostic(1));
    host.reports[1]!.add('{"appVersion": "1.0"}');
    expect(await IosDiagnostics.takeNewDiagnosticReports(), hasLength(1));
    expect(await IosDiagnostics.takeNewDiagnosticReports(), isEmpty);
    host.reports[0]!.add(diagnostic(2));
    expect(await IosDiagnostics.takeNewDiagnosticReports(), hasLength(1));
    final metrics = await IosDiagnostics.takeNewMetricReports();
    expect(metrics.single.appVersion, '1.0');
    expect(await IosDiagnostics.getMetricReports(), hasLength(1));
  });

  test('clear and summary reach the host', () async {
    await IosDiagnostics.clearReports();
    expect(host.cleared, isTrue);
    expect(
      await IosDiagnostics.setProcessStateSummaryText('screen=cart'),
      isTrue,
    );
    expect(utf8.decode(host.summary!), 'screen=cart');
    await IosDiagnostics.setProcessStateSummary(null);
    expect(host.summary, isNull);
  });

  test('summaries longer than 128 bytes are rejected before the host', () {
    expect(
      () => IosDiagnostics.setProcessStateSummary(Uint8List(129)),
      throwsArgumentError,
    );
    expect(host.summary, isNull);
  });

  test('arrivals map to report kinds and unknown codes are dropped', () async {
    final kinds = IosDiagnostics.reportsArrived.toList();
    arrivals
      ..add(1)
      ..add(5)
      ..add(0);
    await arrivals.close();
    expect(await kinds, [
      MetricKitReportKind.metric,
      MetricKitReportKind.diagnostic,
    ]);
  });

  test('iOS is the default platform only on iOS', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(UnsupportedIosDiagnostics(), isA<IosDiagnosticsPlatform>());
    debugDefaultTargetPlatformOverride = null;
  });

  test('outside iOS everything degrades to empty answers', () async {
    IosDiagnosticsPlatform.instance = UnsupportedIosDiagnostics();
    expect(await IosDiagnostics.getSupport(), same(MetricKitSupport.none));
    expect(await IosDiagnostics.getDiagnosticReports(), isEmpty);
    expect(await IosDiagnostics.takeNewMetricReports(), isEmpty);
    expect(await IosDiagnostics.setProcessStateSummaryText('x'), isFalse);
    expect(await IosDiagnostics.reportsArrived.isEmpty, isTrue);
  });
}
