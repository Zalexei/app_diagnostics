# android_diagnostics

Find out **why your Flutter app's Android process died** and **profile it on
real users' devices**, with two system APIs:

- [`ApplicationExitInfo`](https://developer.android.com/reference/android/app/ApplicationExitInfo)
  (Android 11+): the reason for every recent process death (ANR, Java crash,
  native crash, low memory kill, force stop, package update, ...), memory at
  the time of death, the ANR stack dump and the native crash tombstone.
- [`ProfilingManager`](https://developer.android.com/reference/android/os/ProfilingManager)
  (Android 15+): Java heap dumps, heap profiles, CPU stack sampling and
  Perfetto system traces on request, plus system triggers (Android 16+) that
  capture a profile when an ANR, OOM or kill happens.

Crash reporters see exceptions while the process is alive. They miss what
kills it from the outside: the low memory killer, ANRs dismissed by the user,
"Force stop", a native crash in a plugin. The next launch can read all of
that here.

Android only, yet safe to call anywhere: on old Android versions and on other
platforms unsupported features return empty lists, `null`, `false` or
`ProfilingError.unsupported` instead of throwing.

| Exit reasons after a restart | ANR trace | Native crash tombstone | Profiling |
|---|---|---|---|
| ![exit reasons](https://raw.githubusercontent.com/Zalexei/android_diagnostics/main/doc/screenshots/exit_reasons.png) | ![ANR](https://raw.githubusercontent.com/Zalexei/android_diagnostics/main/doc/screenshots/anr_trace.png) | ![tombstone](https://raw.githubusercontent.com/Zalexei/android_diagnostics/main/doc/screenshots/native_tombstone.png) | ![profiling](https://raw.githubusercontent.com/Zalexei/android_diagnostics/main/doc/screenshots/profiling.png) |

## What works on which Android version

| Feature | API | Android | On older versions |
|---|---|---|---|
| `getExitReasons`, `takeNewExitReasons` | 30 | 11 | empty list |
| `setProcessStateSummary` (128 bytes, read back after death) | 30 | 11 | returns `false` |
| ANR stack dump: `getAnrTrace` | 30 | 11 | `null` |
| Native crash tombstone: `getNativeTombstone` | 31 | 12 | `null` |
| Reasons `freezer` / `packageStateChange`, `packageUpdated` | 33 / 34 | 13 / 14 | not reported by the system |
| `startProfiling`, `profile` (4 profile types), `profilingResults` | 35 | 15 | result `ProfilingError.unsupported`, empty stream |
| Triggers `appFullyDrawn`, `anr` | 36 | 16 | skipped by `addProfilingTriggers` |
| `requestRunningSystemTrace`; triggers `appRequestRunningTrace`, `killForceStop`, `killRecents`, `killTaskManager` | 36.1 | 16 (minor SDK 36.1) | `false` / skipped |
| `ExitInfo.anrInfo`; triggers `oom`, `anomaly`, `killExcessiveCpuUsage`, `coldStart`, `appCompat` | 37 | 17 | `null` / skipped |
| Reasons `memoryLimiter`, `anomaly` | 37.2 | 17 (minor SDK 37.2) | not reported by the system |

`AndroidDiagnostics.getSupport()` tells you what the current device offers.

## Install

```yaml
dependencies:
  android_diagnostics: ^0.1.0
```

Requirements: Flutter 3.35+, app `compileSdk` 35+ (the plugin uses
`androidx.core:core:1.15.0`), `minSdk` 24. No permissions needed.

## Report why the previous process died

`takeNewExitReasons()` returns each record once across launches (the marker
is persisted), so call it on startup and send the result wherever you
collect telemetry:

```dart
import 'package:android_diagnostics/android_diagnostics.dart';

Future<void> reportPreviousDeaths() async {
  for (final exit in await AndroidDiagnostics.takeNewExitReasons()) {
    if (!exit.isAppProblem) continue; // skip force stops, updates, ...
    analytics.log('process_exit', exit.toJson());
    // {reason: anr, importance: foreground, rssKb: 336784,
    //  description: user request after error: Input dispatching timed out ...,
    //  processStateSummary: screen=checkout, ...}
  }
}
```

`getExitReasons(maxNum: 20)` returns the whole history the system keeps
(a ring buffer of recent deaths, newest first) without touching the marker.

### ANR stack dump and native crash tombstone

```dart
final exits = await AndroidDiagnostics.getExitReasons();
for (final exit in exits.where((e) => e.hasTrace)) {
  switch (exit.reason) {
    case ExitReason.anr:
      // Text dump of all threads; look for the "main" thread.
      final text = await AndroidDiagnostics.getAnrTrace(exit);
      upload('anr-${exit.pid}.txt', text);
    case ExitReason.crashNative:
      // Android 12+: the protobuf tombstone, decoded in Dart.
      final tombstone = await AndroidDiagnostics.getNativeTombstone(exit);
      print(tombstone?.signal?.name);   // SIGABRT
      print(tombstone?.abortMessage);   // the message passed to abort()
      print(tombstone?.toText());       // logcat-style report with backtrace
    default:
      break;
  }
}
```

`getTraceBytes(exit)` gives the raw bytes if you want to ship them as is.
Traces live in a system-wide circular buffer, so read them on the first
launch after the death. The system keeps no stack trace for Java crashes
(`ExitReason.crash`): use your crash reporter for those.

`NativeTombstone` decodes the build, process, signal, abort message, causes
and the backtrace of every thread
([tombstone.proto](https://android.googlesource.com/platform/system/core/+/refs/heads/main/debuggerd/proto/tombstone.proto)).
Frames carry `relPc` and `buildId`, ready for `ndk-stack` or `llvm-symbolizer`.

### Leave a note for the next launch

Up to 128 bytes that survive the process death and come back in
`ExitInfo.processStateSummary`:

```dart
await AndroidDiagnostics.setProcessStateSummaryText('screen=checkout;exp=new_cart');
```

Keep it short and free of personal data. The system may throttle frequent
calls (the method then returns `false`).

## Profile on users' devices (Android 15+)

```dart
// One-shot heap dump.
final dump = await AndroidDiagnostics.profile(
  const ProfilingRequest.javaHeapDump(tag: 'big-list'),
);

// Continuous profile around the code you care about.
final session = AndroidDiagnostics.startProfiling(
  const ProfilingRequest.systemTrace(tag: 'checkout', duration: Duration(seconds: 30)),
);
await openCheckout();
await session.stop(); // end early; otherwise it stops after `duration`
final result = await session.result;

if (result.isSuccess) {
  upload(result.filePath!); // open in https://ui.perfetto.dev
} else {
  print(result.error); // rateLimitSystem, profilingInProgress, unsupported, ...
}
```

Request types: `javaHeapDump`, `heapProfile` (native or Java allocations),
`stackSampling`, `systemTrace` (with `BufferFillPolicy.ringBuffer` to keep the
end of a long window). All parameters are optional; the system clamps them to
its limits. Results are files in the app's `files/profiling` folder: upload
and delete them yourself (`listProfilingFiles()` lists them).

### Triggers (Android 16+)

The system captures a profile when something happens, even if the process
dies:

```dart
final sub = AndroidDiagnostics.profilingResults.listen((result) {
  if (result.isSuccess && result.trigger != ProfilingTriggerType.none) {
    upload(result.filePath!);
  }
});

final registered = await AndroidDiagnostics.addProfilingTriggers(const [
  ProfilingTrigger(ProfilingTriggerType.anr, rateLimitingPeriodHours: 24),
  ProfilingTrigger(ProfilingTriggerType.oom), // Android 17+: Java heap dump on OutOfMemoryError
  ProfilingTrigger(ProfilingTriggerType.appRequestRunningTrace),
]);
// `registered` holds only the triggers this device supports.

// Later, when something looks slow (SDK 36.1+):
await AndroidDiagnostics.requestRunningSystemTrace(tag: 'slow-scroll');
```

Results of a trigger that fired while the process was dying (OOM, kills)
arrive in the **next** process, as soon as it listens to `profilingResults`.
Subscribe early (e.g. in `main`). Files delivered while nobody listened are
still in `listProfilingFiles()`.

The OOM trigger needs any custom `Thread.UncaughtExceptionHandler` to call
through to the default one.

## Testing locally

```bash
# Disable profiling rate limits on a test device
adb shell device_config put profiling_testing rate_limiter.disabled true
# Keep a background trace running and let triggers fire for your app
adb shell device_config put profiling_testing system_triggered_profiling.testing_package_name com.your.app
# What the system recorded about your app's deaths
adb shell dumpsys activity exit-info com.your.app
```

In your own tests, replace the platform with a fake:

```dart
AndroidDiagnosticsPlatform.instance = MyFakeDiagnostics();
```

## Example app

[`example/`](example) has a crash lab (ANR, OOM, native crash via
`__android_log_assert`, Java crash), shows the exit records with their traces
after a restart, and runs every profiling type and trigger.
`tool/crash_scenarios.sh SERIAL` drives the four crash scenarios over adb.

Verified on an Android 17 (API 37.1) Pixel 9a emulator: all four deaths are
reported after restart with the process state summary; the ANR record carries
the main thread stack (`Thread.sleep` in the crash lab), the native crash
record decodes to `SIGABRT` with the abort message and backtrace; all four
profiling types return files; the running trace snapshot and the OOM heap
dump arrive through `profilingResults`, and so does the system trace of the
ANR trigger (the last two in the next process).

## Notes

- `pssKb` / `rssKb` are the last sampled values, often 0 when the system did
  not sample the process before it died.
- `AnrInfo.timeout` is passed through from the platform as is; its meaning
  differs from the input dispatch timeout shown in `description`.
- The plugin compiles against API 36 and reaches the newer API 36.1 / 37
  methods (`requestRunningSystemTrace`, `getAnrInfo`) through reflection,
  guarded by `Build.VERSION.SDK_INT_FULL`.
