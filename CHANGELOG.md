## 0.1.2

* Every public class, enum value, field, constructor and method now has API
  docs (about 210 additions): exit reasons and process importance map to
  their Android meaning, tombstone and MetricKit fields say where the value
  comes from and what a missing value turns into, and the platform interfaces
  describe each call.
* The `public_member_api_docs` lint is on, so new public API must be
  documented. No code changes.

## 0.1.1

* Android: on Flutter 3.44+ apps no longer warn that app_diagnostics applies
  the Kotlin Gradle Plugin. With AGP 9 and built-in Kotlin the plugin lets
  AGP compile Kotlin; elsewhere it applies KGP as before. Flutter 3.35+ is
  still supported.
* Example builds on Flutter 3.50 (Gradle 9.5, AGP 9.3.1, Kotlin 2.4.20).

## 0.1.0

* First release.
* Android, `AndroidDiagnostics`:
  * `ApplicationExitInfo`: exit reasons with importance, PSS/RSS, description,
    process state summary and `AnrInfo` (API 37); `takeNewExitReasons()` with
    a persisted marker; ANR stack dumps; native crash tombstones decoded in
    Dart.
  * `setProcessStateSummary` / `setProcessStateSummaryText`.
  * `ProfilingManager`: Java heap dump, heap profile, stack sampling and
    system trace requests with early stop; system triggers (API 36+), running
    trace snapshots (API 36.1), a stream of all results, listing of delivered
    files.
* iOS, `IosDiagnostics` (MetricKit), **beta**: not yet verified with reports
  from a real device:
  * Crash, hang, CPU exception, disk write exception and slow launch
    diagnostics with call stack trees of any depth, kept on disk until read,
    each with a stable `id` and MetricKit's JSON byte for byte;
    `takeNewDiagnosticReports()` with a persisted marker; `reportsArrived`
    also fires on listen when unread reports wait.
  * Daily exit counts (foreground and background) and peak memory.
  * A process state summary that comes back with crashes of the same pid
    (iOS 17+).
* Safe on every OS version and on other platforms.
