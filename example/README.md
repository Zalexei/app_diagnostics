# app_diagnostics example

## Minimal use

Report why the previous process died, on both platforms:

```dart
import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Android 11+: every death since the previous launch, once.
  for (final exit in await AndroidDiagnostics.takeNewExitReasons()) {
    if (exit.isAppProblem) send('android_exit', exit.toJson());
  }

  // iOS 14+: MetricKit crash and hang reports, once. The stream also fires
  // right away when unread reports are waiting.
  IosDiagnostics.reportsArrived.listen((_) async {
    for (final report in await IosDiagnostics.takeNewDiagnosticReports()) {
      for (final d in report.diagnostics) {
        send('ios_diagnostic', {'id': report.id, 'title': d.title});
      }
    }
  });

  // Both: a note that comes back with the next crash report.
  await AndroidDiagnostics.setProcessStateSummaryText('screen=home');
  await IosDiagnostics.setProcessStateSummaryText('screen=home');

  runApp(const SizedBox());
}

void send(String event, Map<String, Object?> data) {
  // Your analytics or crash reporter.
}
```

Profile a slow screen on an Android 15+ device:

```dart
final session = AndroidDiagnostics.startProfiling(
  const ProfilingRequest.systemTrace(duration: Duration(seconds: 10)),
);
await openSlowScreen();
await session.stop();
final result = await session.result;
print(result.isSuccess ? result.filePath : result.error); // open in ui.perfetto.dev
```

## The example app

Crash lab and profiling playground for `app_diagnostics`.

## Android

1. Run it on an Android 11+ device or emulator (Android 15+ for profiling,
   17 for every feature).
2. Press **ANR**, **OOM**, **Native crash** or **Java crash**. For the ANR,
   touch the screen while the main thread is frozen and choose "Close app" in
   the system dialog.
3. Start the app again: the record is at the bottom, marked `NEW`, with the
   process state summary the app stored before dying. Tap records marked
   `trace` to read the ANR stack dump or the decoded native tombstone.
4. The profiling buttons request each profile type; **Register triggers** and
   **Snapshot running trace** exercise system triggers.

For profiling on a test device:

```bash
adb shell device_config put profiling_testing rate_limiter.disabled true
adb shell device_config put profiling_testing system_triggered_profiling.testing_package_name io.github.zalexei.app_diagnostics_example
```

`../tool/crash_scenarios.sh SERIAL` runs the four crash scenarios over adb.

## iOS

1. Run it on an iPhone (iOS 15+ for diagnostics on the next launch). The
   simulator builds and runs the app, but MetricKit never delivers reports
   there.
2. Press **Hang 8 s**, **Native crash** (`abort()` through Dart FFI),
   **ObjC exception** or **OOM**.
3. Start the app again: MetricKit delivers the diagnostic a few seconds after
   launch, the list updates and marks it `NEW`. Tap it for the metadata, the
   process state summary (iOS 17+) and the call stacks. Daily exit counts
   arrive once a day.
4. With the app running from Xcode on a device, Debug › Simulate MetricKit
   Payloads delivers sample reports right away.

The iOS 27 SDK requires the UIScene life cycle: `ios/Runner/AppDelegate.swift`
creates the Flutter engine in the app delegate and shows it from a scene
delegate. With Flutter 3.35 and Xcode 27, `flutter build ios --simulator`
fails in `lipo -verify_arch`; build for one architecture instead, e.g.
`flutter run` or `xcodebuild ... ONLY_ACTIVE_ARCH=YES`.
