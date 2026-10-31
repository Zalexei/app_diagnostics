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
* iOS, `IosDiagnostics` (MetricKit):
  * Crash, hang, CPU exception, disk write exception and slow launch
    diagnostics with call stack trees, kept on disk until read;
    `takeNewDiagnosticReports()` with a persisted marker.
  * Daily exit counts (foreground and background) and peak memory.
  * A process state summary that comes back with crashes of the same pid
    (iOS 17+).
* Safe on every OS version and on other platforms.
