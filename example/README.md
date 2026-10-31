# app_diagnostics example

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
