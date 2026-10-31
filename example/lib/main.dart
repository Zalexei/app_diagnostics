import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:android_diagnostics/android_diagnostics.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(
    const MaterialApp(title: 'android_diagnostics', home: DiagnosticsHome()),
  );
}

const _crashLab = MethodChannel('android_diagnostics_example/crash_lab');

/// `__android_log_assert` from liblog: writes the abort message and calls
/// abort(), so the tombstone carries a readable message.
void _nativeCrash() {
  final assertFn = DynamicLibrary.open('liblog.so')
      .lookupFunction<
        Void Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>),
        void Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>)
      >('__android_log_assert');
  assertFn(
    nullptr,
    'crash_lab'.toNativeUtf8(),
    'crash_lab: native crash from Dart FFI'.toNativeUtf8(),
  );
}

class DiagnosticsHome extends StatefulWidget {
  const DiagnosticsHome({super.key});

  @override
  State<DiagnosticsHome> createState() => _DiagnosticsHomeState();
}

class _DiagnosticsHomeState extends State<DiagnosticsHome> {
  DiagnosticsSupport? _support;
  List<ExitInfo> _exits = const [];
  Set<int> _newExits = const {};
  List<String> _files = const [];
  final List<String> _profilingLog = [];
  List<ProfilingTriggerType> _triggers = const [];
  ProfilingSession? _running;
  StreamSubscription<ProfilingResult>? _results;

  @override
  void initState() {
    super.initState();
    _results = AndroidDiagnostics.profilingResults.listen((r) {
      if (r.trigger != ProfilingTriggerType.none) {
        _log('Trigger ${r.trigger.name}: $r');
      }
      _refreshFiles();
    });
    _load();
  }

  @override
  void dispose() {
    _results?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final support = await AndroidDiagnostics.getSupport();
    final fresh = await AndroidDiagnostics.takeNewExitReasons();
    final exits = await AndroidDiagnostics.getExitReasons(maxNum: 30);
    await AndroidDiagnostics.setProcessStateSummaryText('screen=home');
    if (!mounted) return;
    setState(() {
      _support = support;
      _exits = exits;
      _newExits = {
        ..._newExits,
        for (final e in fresh) e.timestamp.millisecondsSinceEpoch,
      };
    });
    await _refreshFiles();
  }

  Future<void> _refreshFiles() async {
    final files = await AndroidDiagnostics.listProfilingFiles();
    if (mounted) setState(() => _files = files);
  }

  void _log(String line) {
    if (!mounted) return;
    setState(() => _profilingLog.insert(0, '${_clock()} $line'));
  }

  static String _clock() {
    final d = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

  Future<void> _crash(String kind) async {
    // Read back after the restart from ExitInfo.processStateSummary.
    await AndroidDiagnostics.setProcessStateSummaryText(
      'lab=$kind at ${_clock()}',
    );
    if (kind == 'anr' && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 10),
          content: Text(
            'Main thread frozen for 60 s. Tap the screen, wait for the ANR dialog, choose "Close app".',
          ),
        ),
      );
    }
    if (kind == 'native') {
      _nativeCrash();
    } else {
      await _crashLab.invokeMethod<void>(kind);
    }
  }

  Future<void> _profile(String label, ProfilingRequest request) async {
    final session = AndroidDiagnostics.startProfiling(request);
    setState(() => _running = session);
    _log('$label requested');
    final result = await session.result;
    if (!mounted) return;
    setState(() => _running = null);
    _log(
      result.isSuccess
          ? '$label OK: ${result.filePath!.split('/').last} (${_size(result.filePath!)})'
          : '$label failed: ${result.error.name} ${result.errorMessage ?? ''}',
    );
    await _refreshFiles();
  }

  Future<void> _registerTriggers() async {
    final added = await AndroidDiagnostics.addProfilingTriggers([
      for (final type in [
        ProfilingTriggerType.anr,
        ProfilingTriggerType.oom,
        ProfilingTriggerType.appRequestRunningTrace,
        ProfilingTriggerType.killRecents,
        ProfilingTriggerType.killForceStop,
      ])
        ProfilingTrigger(type, rateLimitingPeriodHours: 1),
    ]);
    setState(() => _triggers = added);
    _log(
      'Triggers registered: ${added.isEmpty ? 'none (needs Android 16)' : added.map((t) => t.name).join(', ')}',
    );
  }

  Future<void> _snapshot() async {
    final ok = await AndroidDiagnostics.requestRunningSystemTrace(
      tag: 'snapshot',
    );
    _log(
      ok
          ? 'Running trace snapshot requested'
          : 'Running trace snapshot not supported',
    );
  }

  static String _size(String path) {
    try {
      final kb = File(path).lengthSync() / 1024;
      return kb > 1024
          ? '${(kb / 1024).toStringAsFixed(1)} MB'
          : '${kb.toStringAsFixed(0)} KB';
    } on FileSystemException {
      return '?';
    }
  }

  @override
  Widget build(BuildContext context) {
    final support = _support;
    return Scaffold(
      appBar: AppBar(
        title: const Text('android_diagnostics'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
          ),
        ],
      ),
      body: support == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _SupportCard(support),
                  _Section(
                    title: 'Crash lab',
                    subtitle:
                        'Kill the app, start it again, find the record below.',
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.tonal(
                            onPressed: () => _crash('anr'),
                            child: const Text('ANR'),
                          ),
                          FilledButton.tonal(
                            onPressed: () => _crash('oom'),
                            child: const Text('OOM'),
                          ),
                          FilledButton.tonal(
                            onPressed: () => _crash('native'),
                            child: const Text('Native crash'),
                          ),
                          FilledButton.tonal(
                            onPressed: () => _crash('javaCrash'),
                            child: const Text('Java crash'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  _ProfilingCard(
                    support: support,
                    running: _running,
                    triggers: _triggers,
                    log: _profilingLog,
                    files: _files,
                    onProfile: _profile,
                    onRegisterTriggers: _registerTriggers,
                    onSnapshot: _snapshot,
                  ),
                  _Section(
                    title: 'Exit reasons (${_exits.length})',
                    subtitle: support.exitReasons
                        ? 'Newest first. Tap a record marked "trace".'
                        : 'Needs Android 11 (API 30).',
                    children: [
                      for (final e in _exits)
                        _ExitTile(
                          e,
                          isNew: _newExits.contains(
                            e.timestamp.millisecondsSinceEpoch,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, this.subtitle, required this.children});

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            if (subtitle != null)
              Text(subtitle!, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _SupportCard extends StatelessWidget {
  const _SupportCard(this.support);

  final DiagnosticsSupport support;

  @override
  Widget build(BuildContext context) {
    final minor = support.sdkIntFull % 100000;
    Widget chip(String label, bool on) => Chip(
      avatar: Icon(
        on ? Icons.check_circle : Icons.cancel,
        size: 18,
        color: on ? Colors.green : Colors.grey,
      ),
      label: Text(label),
    );
    return _Section(
      title: 'Android API ${support.sdkInt}${minor > 0 ? '.$minor' : ''}',
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            chip('Exit reasons (30)', support.exitReasons),
            chip('Native tombstones (31)', support.nativeTombstones),
            chip('Profiling (35)', support.profiling),
            chip('Triggers (36)', support.profilingTriggers),
            chip('Trace snapshot (36.1)', support.runningTraceSnapshot),
            chip('AnrInfo (37)', support.anrInfo),
          ],
        ),
      ],
    );
  }
}

class _ProfilingCard extends StatelessWidget {
  const _ProfilingCard({
    required this.support,
    required this.running,
    required this.triggers,
    required this.log,
    required this.files,
    required this.onProfile,
    required this.onRegisterTriggers,
    required this.onSnapshot,
  });

  final DiagnosticsSupport support;
  final ProfilingSession? running;
  final List<ProfilingTriggerType> triggers;
  final List<String> log;
  final List<String> files;
  final void Function(String label, ProfilingRequest request) onProfile;
  final VoidCallback onRegisterTriggers;
  final VoidCallback onSnapshot;

  @override
  Widget build(BuildContext context) {
    const window = Duration(seconds: 5);
    final busy = running != null;
    final mono = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace');
    Widget request(String label, ProfilingRequest r) => OutlinedButton(
      onPressed: busy ? null : () => onProfile(label, r),
      child: Text(label),
    );
    return _Section(
      title: 'Profiling',
      subtitle: support.profiling
          ? 'Requests are rate limited. For testing: adb shell device_config put '
                'profiling_testing rate_limiter.disabled true'
          : 'Needs Android 15 (API 35): requests answer "unsupported".',
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            request(
              'Java heap dump',
              const ProfilingRequest.javaHeapDump(tag: 'heap-dump'),
            ),
            request(
              'Heap profile 5 s',
              const ProfilingRequest.heapProfile(
                tag: 'heap-profile',
                duration: window,
              ),
            ),
            request(
              'Stack sampling 5 s',
              const ProfilingRequest.stackSampling(
                tag: 'stack',
                duration: window,
              ),
            ),
            request(
              'System trace 5 s',
              const ProfilingRequest.systemTrace(
                tag: 'trace',
                duration: window,
              ),
            ),
            if (busy)
              TextButton(
                onPressed: running!.stop,
                child: const Text('Stop now'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: onRegisterTriggers,
              child: const Text('Register triggers'),
            ),
            OutlinedButton(
              onPressed: onSnapshot,
              child: const Text('Snapshot running trace'),
            ),
          ],
        ),
        if (triggers.isNotEmpty)
          Text('Triggers: ${triggers.map((t) => t.name).join(', ')}'),
        for (final line in log.take(8)) Text(line, style: mono),
        if (files.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('files/profiling (${files.length}):'),
          for (final f in files.take(6)) Text(f.split('/').last, style: mono),
        ],
      ],
    );
  }
}

class _ExitTile extends StatelessWidget {
  const _ExitTile(this.info, {required this.isNew});

  final ExitInfo info;
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    final summary = info.processStateSummaryText;
    final details = [
      info.timestamp.toString().substring(0, 19),
      'importance ${info.importance.name}, pss ${info.pssKb ~/ 1024} MB, rss ${info.rssKb ~/ 1024} MB',
      if (info.description != null) 'description: ${info.description}',
      if (summary != null) 'summary: $summary',
      if (info.anrInfo != null)
        'ANR timeout ${info.anrInfo!.timeout.inMilliseconds} ms',
    ];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        info.isAppProblem ? Icons.error : Icons.info_outline,
        color: info.isAppProblem ? Colors.red : null,
      ),
      title: Text(
        '${info.reason.name}${isNew ? '  • NEW' : ''}${info.hasTrace ? '  • trace' : ''}',
      ),
      subtitle: Text(details.join('\n')),
      isThreeLine: true,
      onTap: info.hasTrace
          ? () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => TraceScreen(info)))
          : null,
    );
  }
}

class TraceScreen extends StatefulWidget {
  const TraceScreen(this.info, {super.key});

  final ExitInfo info;

  @override
  State<TraceScreen> createState() => _TraceScreenState();
}

class _TraceScreenState extends State<TraceScreen> {
  late final Future<String> _text = _load();

  Future<String> _load() async {
    final info = widget.info;
    if (info.reason == ExitReason.crashNative) {
      final tombstone = await AndroidDiagnostics.getNativeTombstone(info);
      if (tombstone != null) return tombstone.toText();
    }
    if (info.reason == ExitReason.anr) {
      final text = await AndroidDiagnostics.getAnrTrace(info);
      if (text != null) return text;
    }
    final bytes = await AndroidDiagnostics.getTraceBytes(info);
    return bytes == null
        ? 'The system no longer keeps this trace.'
        : '${bytes.length} bytes of trace data';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.info.reason.name}, pid ${widget.info.pid}'),
      ),
      body: FutureBuilder<String>(
        future: _text,
        builder: (context, snapshot) => snapshot.hasData
            ? SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  snapshot.data!,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              )
            : const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
