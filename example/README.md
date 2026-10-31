# android_diagnostics example

Crash lab and profiling playground for `android_diagnostics`.

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
adb shell device_config put profiling_testing system_triggered_profiling.testing_package_name io.github.zalexei.android_diagnostics_example
```

`../tool/crash_scenarios.sh SERIAL` runs the four crash scenarios over adb.
