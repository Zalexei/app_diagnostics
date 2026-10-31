## 0.1.0

* First release.
* `ApplicationExitInfo`: exit reasons with importance, PSS/RSS, description,
  process state summary and `AnrInfo` (API 37); `takeNewExitReasons()` with a
  persisted marker; ANR stack dumps; native crash tombstones decoded in Dart.
* `setProcessStateSummary` / `setProcessStateSummaryText`.
* `ProfilingManager`: Java heap dump, heap profile, stack sampling and system
  trace requests with early stop; system triggers (API 36+), running trace
  snapshots (API 36.1), a stream of all results, listing of delivered files.
* Safe on every Android version and on other platforms.
