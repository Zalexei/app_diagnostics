import 'dart:async';
import 'dart:ffi';

import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _crashLab = MethodChannel('app_diagnostics_example/crash_lab');

/// MetricKit reports and an iOS crash lab.
class IosDiagnosticsHome extends StatefulWidget {
  const IosDiagnosticsHome({super.key});

  @override
  State<IosDiagnosticsHome> createState() => _IosDiagnosticsHomeState();
}

class _IosDiagnosticsHomeState extends State<IosDiagnosticsHome> {
  MetricKitSupport? _support;
  List<MetricKitDiagnosticReport> _diagnostics = const [];
  List<MetricKitMetricReport> _metrics = const [];
  final Set<DateTime> _new = {};
  StreamSubscription<MetricKitReportKind>? _arrivals;

  @override
  void initState() {
    super.initState();
    _arrivals = IosDiagnostics.reportsArrived.listen((_) => _load());
    _load();
  }

  @override
  void dispose() {
    _arrivals?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final support = await IosDiagnostics.getSupport();
    final fresh = await IosDiagnostics.takeNewDiagnosticReports();
    await IosDiagnostics.takeNewMetricReports();
    final diagnostics = await IosDiagnostics.getDiagnosticReports();
    final metrics = await IosDiagnostics.getMetricReports();
    if (!mounted) return;
    setState(() {
      _support = support;
      _new.addAll(fresh.map((r) => r.receivedAt));
      _diagnostics = diagnostics;
      _metrics = metrics;
    });
  }

  Future<void> _crash(String kind) async {
    final now = TimeOfDay.now().format(context);
    await IosDiagnostics.setProcessStateSummaryText('lab=$kind at $now');
    if (kind == 'native') {
      // abort() from libc: SIGABRT, reported as an abnormal exit.
      DynamicLibrary.process().lookupFunction<Void Function(), void Function()>(
        'abort',
      )();
    } else {
      await _crashLab.invokeMethod<void>(kind);
    }
  }

  @override
  Widget build(BuildContext context) {
    final support = _support;
    final diagnostics = [
      for (final r in _diagnostics)
        for (final d in r.diagnostics) (r, d),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('app_diagnostics · iOS'),
        actions: [
          IconButton(
            tooltip: 'Delete stored reports',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              await IosDiagnostics.clearReports();
              await _load();
            },
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (support != null)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                Chip(label: Text('iOS ${support.systemVersion}')),
                if (support.isSimulator)
                  const Chip(label: Text('simulator: no MetricKit reports')),
                for (final (name, on) in [
                  ('diagnostics', support.diagnostics),
                  ('next-launch delivery', support.immediateDelivery),
                  ('launch diagnostics', support.appLaunchDiagnostics),
                  ('pid + ObjC reason', support.extendedMetadata),
                ])
                  Chip(
                    avatar: Icon(on ? Icons.check : Icons.close, size: 16),
                    label: Text(name),
                  ),
              ],
            ),
          const SizedBox(height: 12),
          Text('Crash lab', style: Theme.of(context).textTheme.titleMedium),
          const Text(
            'Each button stores a process state summary, then kills or '
            'freezes the app. Reports arrive on the next launch of a device '
            'build (iOS 15+), daily exit counts within a day.',
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: () => _crash('hang'),
                child: const Text('Hang 8 s'),
              ),
              FilledButton(
                onPressed: () => _crash('native'),
                child: const Text('Native crash'),
              ),
              FilledButton(
                onPressed: () => _crash('objcException'),
                child: const Text('ObjC exception'),
              ),
              FilledButton(
                // On the simulator the app would eat the Mac's memory.
                onPressed: support?.isSimulator ?? true
                    ? null
                    : () => _crash('oom'),
                child: const Text('OOM'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Diagnostics (${diagnostics.length})',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (diagnostics.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No diagnostic reports stored yet.'),
            ),
          for (final (report, d) in diagnostics)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _new.contains(report.receivedAt)
                  ? const Badge(label: Text('NEW'))
                  : null,
              title: Text(d.title),
              subtitle: Text(
                '${report.end.toLocal()} · ${d.metadata.appVersion ?? '?'}'
                '${d.processStateSummaryText == null ? '' : ' · ${d.processStateSummaryText}'}',
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      _DiagnosticScreen(report: report, diagnostic: d),
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            'Daily exit counts (${_metrics.length})',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (final m in _metrics)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${m.begin.toLocal()} – ${m.end.toLocal()}'),
              subtitle: Text(
                'foreground: ${m.foregroundExits?.toJson() ?? '-'}\n'
                'background: ${m.backgroundExits?.toJson() ?? '-'}',
              ),
            ),
        ],
      ),
    );
  }
}

class _DiagnosticScreen extends StatelessWidget {
  const _DiagnosticScreen({required this.report, required this.diagnostic});

  final MetricKitDiagnosticReport report;
  final MetricKitDiagnostic diagnostic;

  @override
  Widget build(BuildContext context) {
    final d = diagnostic;
    final details = [
      'period: ${report.begin.toLocal()} – ${report.end.toLocal()}',
      'metadata: ${d.metadata.toJson()}',
      if (d.processStateSummaryText != null)
        'summary: ${d.processStateSummaryText}',
      if (d case CrashDiagnostic(:final terminationReason?))
        'termination: $terminationReason',
      if (d case CrashDiagnostic(:final exceptionReason?))
        'exception: ${exceptionReason.exceptionName}: '
            '${exceptionReason.composedMessage}',
    ];
    return Scaffold(
      appBar: AppBar(title: Text(d.title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: SelectableText(
          '${details.join('\n')}\n\n${d.callStackTree.toText()}',
          style: const TextStyle(fontFamily: 'Menlo', fontSize: 11),
        ),
      ),
    );
  }
}
