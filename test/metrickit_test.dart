import 'dart:convert';

import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

/// Frame in MXCallStackTree.jsonRepresentation() format.
Map<String, Object?> frame(
  String binary,
  int offset, {
  int samples = 1,
  List<Map<String, Object?>> sub = const [],
}) => {
  'binaryUUID': '70B89F27-1634-3580-A695-57CDB41D7743',
  'offsetIntoBinaryTextSegment': offset,
  'sampleCount': samples,
  'binaryName': binary,
  'address': 0x100000000 + offset,
  if (sub.isNotEmpty) 'subFrames': sub,
};

/// A thread stack: frame 0 first, each next frame nested as the only sub-frame.
Map<String, Object?> thread(bool attributed, List<(String, int)> frames) {
  Map<String, Object?>? nested;
  for (final (binary, offset) in frames.reversed) {
    nested = frame(binary, offset, sub: [?nested]);
  }
  return {
    'threadAttributed': attributed,
    'callStackRootFrames': [?nested],
  };
}

const meta = {
  'appVersion': '1.2.0',
  'appBuildVersion': '42',
  'osVersion': 'iPhone OS 18.2 (22C152)',
  'deviceType': 'iPhone17,1',
  'platformArchitecture': 'arm64e',
  'regionFormat': 'IL',
  'pid': 4711,
  'isTestFlightApp': false,
  'lowPowerModeEnabled': true,
};

/// What the Swift side stores for one MXDiagnosticPayload.
String storedDiagnosticReport() => jsonEncode({
  'receivedAt': 1761900000000,
  'begin': 1761800000000,
  'end': 1761886400000,
  'raw': {
    'timeStampBegin': '2026-10-30 07:33:20',
    'crashDiagnostics': [{}],
  },
  'crashes': [
    {
      'meta': meta,
      'processStateSummary': base64Encode(utf8.encode('screen=checkout')),
      'exceptionType': 1,
      'exceptionCode': 0,
      'signal': 11,
      'terminationReason': 'Namespace SIGNAL, Code 0xb',
      'virtualMemoryRegionInfo': '0 is not in any region.',
      'exceptionReason': {
        'composedMessage':
            '*** -[__NSArrayM objectAtIndex:]: index 5 beyond bounds',
        'formatString':
            '*** -[__NSArrayM objectAtIndex:]: index %lu beyond bounds',
        'arguments': ['5'],
        'exceptionType': 'ObjectiveC',
        'className': 'NSException',
        'exceptionName': 'NSRangeException',
      },
      'callStackTree': {
        'callStackPerThread': true,
        'callStacks': [
          thread(true, [
            ('libsystem_kernel.dylib', 30244),
            ('App', 1234),
            ('Runner', 88),
          ]),
          thread(false, [('libsystem_pthread.dylib', 7000)]),
        ],
      },
    },
  ],
  'hangs': [
    {
      'meta': meta,
      'hangDurationSec': 4.25,
      'callStackTree': {
        'callStackPerThread': true,
        'callStacks': [
          thread(true, [('Foundation', 512)]),
        ],
      },
    },
  ],
  'cpuExceptions': [
    {
      'meta': meta,
      'totalCpuTimeSec': 87.5,
      'totalSampledTimeSec': 180.0,
      'callStackTree': {
        'callStackPerThread': false,
        'callStacks': [
          {
            'threadAttributed': false,
            'callStackRootFrames': [
              frame(
                'App',
                10,
                samples: 40,
                sub: [
                  frame('App', 20, samples: 30),
                  frame('libz.dylib', 30, samples: 10),
                ],
              ),
            ],
          },
        ],
      },
    },
  ],
  'diskWriteExceptions': [
    {'meta': meta, 'totalWritesBytes': 1610612736.0},
  ],
  'appLaunches': [
    {'meta': meta, 'launchDurationSec': 6.3},
  ],
});

String storedMetricReport() => jsonEncode({
  'receivedAt': 1761900000000,
  'begin': 1761782400000,
  'end': 1761868800000,
  'appVersion': '1.2.0',
  'multipleAppVersions': false,
  'meta': meta,
  'foregroundExits': {
    'normal': 12,
    'abnormal': 1,
    'watchdog': 2,
    'memoryResourceLimit': 3,
    'badAccess': 4,
    'illegalInstruction': 0,
  },
  'backgroundExits': {
    'normal': 5,
    'abnormal': 0,
    'watchdog': 0,
    'memoryResourceLimit': 1,
    'badAccess': 0,
    'illegalInstruction': 0,
    'memoryPressure': 30,
    'cpuResourceLimit': 1,
    'suspendedWithLockedFile': 2,
    'backgroundTaskAssertionTimeout': 3,
  },
  'peakMemoryBytes': 412090368.0,
  'raw': {'applicationExitMetrics': {}},
});

void main() {
  group('MetricKitDiagnosticReport', () {
    final report = MetricKitDiagnosticReport.fromJson(storedDiagnosticReport());

    test('keeps the payload period and the raw MetricKit JSON', () {
      expect(report.begin, DateTime.fromMillisecondsSinceEpoch(1761800000000));
      expect(report.end, DateTime.fromMillisecondsSinceEpoch(1761886400000));
      expect(report.receivedAt.millisecondsSinceEpoch, 1761900000000);
      expect(
        jsonDecode(report.rawJson),
        containsPair('crashDiagnostics', [{}]),
      );
      expect(report.diagnostics.map((d) => d.runtimeType), [
        CrashDiagnostic,
        HangDiagnostic,
        CpuExceptionDiagnostic,
        DiskWriteExceptionDiagnostic,
        AppLaunchDiagnostic,
      ]);
    });

    test('decodes a crash with metadata, summary and ObjC exception', () {
      final crash = report.crashes.single;
      expect(crash.exceptionTypeName, 'EXC_BAD_ACCESS');
      expect(crash.signalName, 'SIGSEGV');
      expect(crash.terminationReason, 'Namespace SIGNAL, Code 0xb');
      expect(crash.exceptionReason!.exceptionName, 'NSRangeException');
      expect(crash.exceptionReason!.arguments, ['5']);
      expect(crash.title, 'crash EXC_BAD_ACCESS (SIGSEGV) NSRangeException');
      expect(crash.processStateSummaryText, 'screen=checkout');
      expect(crash.metadata.pid, 4711);
      expect(crash.metadata.deviceType, 'iPhone17,1');
      expect(crash.metadata.lowPowerModeEnabled, isTrue);
      expect(crash.metadata.bundleIdentifier, isNull);
      expect(crash.metadata.toJson(), isNot(contains('bundleIdentifier')));
    });

    test('flattens thread stacks frame 0 first', () {
      final tree = report.crashes.single.callStackTree;
      expect(tree.callStackPerThread, isTrue);
      expect(tree.callStacks, hasLength(2));
      final frames = tree.attributedStack!.frames;
      expect(frames.map((f) => f.binaryName), [
        'libsystem_kernel.dylib',
        'App',
        'Runner',
      ]);
      expect(frames[1].offsetIntoBinaryTextSegment, 1234);
      expect(frames[1].address, 0x100000000 + 1234);
      expect(
        frames[1].format(1),
        '1   App                          0x00000001000004d2 App + 1234',
      );
      final text = tree.toText();
      expect(
        text,
        startsWith('Thread 0 (attributed):\n0   libsystem_kernel.dylib'),
      );
      expect(text, contains('\nThread 1:\n0   libsystem_pthread.dylib'));
    });

    test('measurements become durations and bytes', () {
      expect(
        report.hangs.single.hangDuration,
        const Duration(milliseconds: 4250),
      );
      expect(report.hangs.single.title, 'hang 4.3 s');
      final cpu = report.cpuExceptions.single;
      expect(cpu.totalCpuTime, const Duration(milliseconds: 87500));
      expect(cpu.totalSampledTime, const Duration(minutes: 3));
      expect(cpu.title, 'CPU exception 88 s in 180 s');
      final disk = report.diskWriteExceptions.single;
      expect(disk.totalWritesBytes, 1610612736);
      expect(disk.title, 'disk writes 1536.0 MB');
      expect(disk.callStackTree.callStacks, isEmpty);
      expect(
        report.appLaunches.single.launchDuration,
        const Duration(milliseconds: 6300),
      );
    });

    test('prints sampled trees with sample counts', () {
      expect(
        report.cpuExceptions.single.callStackTree.toText(),
        'Call stack 0:\n'
        '[40] App + 10 (0x10000000a)\n'
        '  [30] App + 20 (0x100000014)\n'
        '  [10] libz.dylib + 30 (0x10000001e)',
      );
    });

    test('unknown exception types and signals keep their numbers', () {
      final r = MetricKitDiagnosticReport.fromJson(
        jsonEncode({
          'crashes': [
            {'exceptionType': 99, 'signal': 31},
          ],
        }),
      );
      final crash = r.crashes.single;
      expect(crash.exceptionTypeName, isNull);
      expect(crash.signalName, isNull);
      expect(crash.title, 'crash exception 99 (signal 31)');
      expect(crash.callStackTree.callStacks, isEmpty);
      expect(crash.processStateSummary, isNull);
      expect(r.begin.millisecondsSinceEpoch, 0);
    });

    test('rejects malformed input with FormatException', () {
      expect(
        () => MetricKitDiagnosticReport.fromJson('[1]'),
        throwsFormatException,
      );
      expect(
        () => MetricKitDiagnosticReport.fromJson('{'),
        throwsFormatException,
      );
      expect(
        () => MetricKitDiagnosticReport.fromJson(
          '{"crashes": [{"terminationReason": 5}]}',
        ),
        throwsFormatException,
      );
    });
  });

  group('MetricKitMetricReport', () {
    final report = MetricKitMetricReport.fromJson(storedMetricReport());

    test('decodes exit counts and peak memory', () {
      expect(report.appVersion, '1.2.0');
      expect(report.metadata!.osVersion, 'iPhone OS 18.2 (22C152)');
      expect(report.peakMemoryBytes, 412090368);
      final fg = report.foregroundExits!;
      expect(fg.memoryResourceLimit, 3);
      expect(fg.memoryPressure, 0);
      expect(fg.problems, 1 + 2 + 3 + 4);
      expect(fg.total, 12 + 10);
      final bg = report.backgroundExits!;
      expect(bg.memoryPressure, 30);
      expect(bg.problems, 1 + 1 + 2 + 3);
      expect(bg.total, 5 + 30 + 7);
      expect(bg.toJson()['backgroundTaskAssertionTimeout'], 3);
    });

    test('reports without exit metrics', () {
      final r = MetricKitMetricReport.fromJson('{"begin": 1, "end": 2}');
      expect(r.foregroundExits, isNull);
      expect(r.backgroundExits, isNull);
      expect(r.metadata, isNull);
      expect(r.raw, isEmpty);
    });
  });

  group('as stored by the Swift side', () {
    // Trees and raw stay JSON text: Foundation cannot parse deep trees.
    final deep = thread(true, [for (var i = 0; i < 300; i++) ('App', i)]);
    const raw =
        '{"crashDiagnostics" : [ ], "timeStampEnd" : "2026-10-31 16:00:00"}';
    final stored = jsonEncode({
      'id': 17,
      'receivedAt': 1761900000000,
      'raw': raw,
      'crashes': [
        {
          'signal': 11,
          'callStackTree': jsonEncode({
            'callStackPerThread': true,
            'callStacks': [deep],
          }),
        },
      ],
    });

    test('decodes trees from JSON text, even 300 frames deep', () {
      final r = MetricKitDiagnosticReport.fromJson(stored);
      expect(r.id, 17);
      expect(
        r.crashes.single.callStackTree.attributedStack!.frames,
        hasLength(300),
      );
    });

    test('keeps MetricKit JSON byte for byte', () {
      final r = MetricKitDiagnosticReport.fromJson(stored);
      expect(r.rawJson, raw);
      expect(r.raw['timeStampEnd'], '2026-10-31 16:00:00');
      expect(
        MetricKitDiagnosticReport(
          begin: _epoch,
          end: _epoch,
          receivedAt: _epoch,
          rawJson: 'not json',
        ).raw,
        isEmpty,
      );
    });

    test('absurd values become FormatException, not other errors', () {
      for (final json in [
        '{"begin": 1e20}',
        '{"hangs": [{"hangDurationSec": 1e305}]}',
        '{"crashes": [{"callStackTree": "[1, 2]"}]}',
      ]) {
        expect(
          () => MetricKitDiagnosticReport.fromJson(json),
          throwsFormatException,
          reason: json,
        );
      }
      expect(
        () => MetricKitMetricReport.fromJson('{"end": 1e20}'),
        throwsFormatException,
      );
    });
  });

  test('report kinds map to the codes of the Swift side', () {
    expect(MetricKitReportKind.diagnostic.code, 0);
    expect(MetricKitReportKind.metric.code, 1);
    expect(MetricKitReportKind.fromCode(7), isNull);
  });
}

final _epoch = DateTime.fromMillisecondsSinceEpoch(0);
