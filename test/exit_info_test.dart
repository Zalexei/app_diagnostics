import 'dart:convert';
import 'dart:typed_data';

import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

ExitInfo exitInfo({
  int reason = 6,
  int importance = 100,
  Uint8List? summary,
  AnrInfo? anr,
}) => ExitInfo(
  reasonCode: reason,
  status: 0,
  importanceCode: importance,
  timestamp: DateTime.utc(2026, 10, 31, 12),
  pid: 4242,
  processName: 'com.example',
  description: 'user request after error',
  pssKb: 1024,
  rssKb: 2048,
  processStateSummary: summary,
  hasTrace: true,
  anrInfo: anr,
);

void main() {
  group('ExitReason', () {
    test('maps every ApplicationExitInfo.REASON_* constant', () {
      // Values from developer.android.com, API 30..37.2.
      const expected = {
        0: ExitReason.unknown,
        1: ExitReason.exitSelf,
        2: ExitReason.signaled,
        3: ExitReason.lowMemory,
        4: ExitReason.crash,
        5: ExitReason.crashNative,
        6: ExitReason.anr,
        7: ExitReason.initializationFailure,
        8: ExitReason.permissionChange,
        9: ExitReason.excessiveResourceUsage,
        10: ExitReason.userRequested,
        11: ExitReason.userStopped,
        12: ExitReason.dependencyDied,
        13: ExitReason.other,
        14: ExitReason.freezer,
        15: ExitReason.packageStateChange,
        16: ExitReason.packageUpdated,
        17: ExitReason.memoryLimiter,
        18: ExitReason.anomaly,
      };
      expected.forEach(
        (code, reason) =>
            expect(ExitReason.fromCode(code), reason, reason: 'code $code'),
      );
    });

    test('future codes fall back to unknown but keep the raw value', () {
      final info = exitInfo(reason: 99);

      expect(info.reason, ExitReason.unknown);
      expect(info.reasonCode, 99);
      expect(info.toJson()['reasonCode'], 99);
    });
  });

  group('ProcessImportance', () {
    test('maps RunningAppProcessInfo.IMPORTANCE_* constants', () {
      expect(ProcessImportance.fromCode(100), ProcessImportance.foreground);
      expect(
        ProcessImportance.fromCode(125),
        ProcessImportance.foregroundService,
      );
      expect(ProcessImportance.fromCode(325), ProcessImportance.topSleeping);
      expect(ProcessImportance.fromCode(400), ProcessImportance.cached);
      expect(ProcessImportance.fromCode(1000), ProcessImportance.gone);
      expect(ProcessImportance.fromCode(7), ProcessImportance.unknown);
    });
  });

  group('ExitInfo', () {
    test('decodes the process state summary as UTF-8', () {
      final info = exitInfo(
        summary: Uint8List.fromList(utf8.encode('screen=checkout;ab=new-cart')),
      );

      expect(info.processStateSummaryText, 'screen=checkout;ab=new-cart');
      expect(exitInfo().processStateSummaryText, isNull);
    });

    test('isAppProblem separates app faults from user and system actions', () {
      expect(exitInfo(reason: 6).isAppProblem, isTrue);
      expect(exitInfo(reason: 5).isAppProblem, isTrue);
      expect(exitInfo(reason: 3).isAppProblem, isTrue);
      expect(exitInfo(reason: 10).isAppProblem, isFalse);
      expect(exitInfo(reason: 16).isAppProblem, isFalse);
    });

    test('toJson is ready for analytics', () {
      final json = exitInfo(
        anr: const AnrInfo(
          anrType: 5,
          anrId: 2707,
          timeout: Duration(seconds: 5),
          userPerceptible: true,
        ),
      ).toJson();

      expect(json['reason'], 'anr');
      expect(json['importance'], 'foreground');
      expect(json['timestamp'], '2026-10-31T12:00:00.000Z');
      expect(json['anrInfo'], {
        'anrType': 5,
        'anrId': 2707,
        'timeoutMs': 5000,
        'userPerceptible': true,
      });
      expect(jsonEncode(json), isA<String>());
    });
  });

  group('DiagnosticsSupport', () {
    const android16 = DiagnosticsSupport(
      sdkInt: 36,
      sdkIntFull: 3600000,
      exitReasons: true,
      nativeTombstones: true,
      anrInfo: false,
      profiling: true,
      profilingTriggers: true,
      runningTraceSnapshot: false,
    );

    test('supportsTrigger respects minor SDK versions', () {
      expect(android16.supportsTrigger(ProfilingTriggerType.anr), isTrue);
      expect(
        android16.supportsTrigger(ProfilingTriggerType.killRecents),
        isFalse,
      ); // 36.1
      expect(
        android16.supportsTrigger(ProfilingTriggerType.oom),
        isFalse,
      ); // 37
      expect(android16.supportsTrigger(ProfilingTriggerType.none), isFalse);
      expect(
        DiagnosticsSupport.none.supportsTrigger(ProfilingTriggerType.anr),
        isFalse,
      );
    });
  });

  group('Profiling enums', () {
    test('trigger codes match ProfilingTrigger.TRIGGER_TYPE_*', () {
      expect(
        [for (final t in ProfilingTriggerType.values) t.code],
        [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, -1],
      );
      expect(ProfilingTriggerType.fromCode(42), ProfilingTriggerType.unknown);
      expect(ProfilingTriggerType.killForceStop.minSdkFull, 3600001);
    });

    test('error codes match ProfilingResult.ERROR_*', () {
      expect(ProfilingError.fromCode(0), ProfilingError.none);
      expect(ProfilingError.fromCode(2), ProfilingError.rateLimitProcess);
      expect(ProfilingError.fromCode(7), ProfilingError.invalidRequest);
      expect(ProfilingError.fromCode(-1), ProfilingError.unsupported);
      expect(ProfilingError.fromCode(123), ProfilingError.unknown);
    });

    test('a result is a success only with a file', () {
      expect(
        const ProfilingResult(
          errorCode: 0,
          filePath: '/data/x.perfetto-trace',
        ).isSuccess,
        isTrue,
      );
      expect(const ProfilingResult(errorCode: 0).isSuccess, isFalse);
      expect(
        const ProfilingResult(errorCode: 1).error,
        ProfilingError.rateLimitSystem,
      );
    });
  });
}
