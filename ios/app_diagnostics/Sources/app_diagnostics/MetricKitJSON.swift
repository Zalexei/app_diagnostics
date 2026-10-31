import Foundation
import MetricKit

/// Turns MetricKit payloads into the JSON that lib/src/metrickit.dart parses.
/// Values come from the typed properties (durations in seconds, sizes in
/// bytes); MetricKit's own jsonRepresentation() formats them as localized
/// strings, so it is only kept as "raw" for uploading as is. Call stack trees
/// and "raw" stay JSON text: Foundation refuses JSON nested deeper than 512
/// levels, which a call stack of ~250 frames already is, and Dart has no such
/// limit.
@available(iOS 14.0, *)
enum MetricKitJSON {
  static func diagnostics(_ p: MXDiagnosticPayload, summary: (Int) -> String?) -> [String: Any] {
    var out = envelope(begin: p.timeStampBegin, end: p.timeStampEnd, raw: p.jsonRepresentation())

    out["crashes"] = (p.crashDiagnostics ?? []).map { d -> [String: Any] in
      var m = common(d, tree: d.callStackTree, summary: summary)
      put(&m, "exceptionType", d.exceptionType?.intValue)
      put(&m, "exceptionCode", d.exceptionCode?.intValue)
      put(&m, "signal", d.signal?.intValue)
      put(&m, "terminationReason", d.terminationReason)
      put(&m, "virtualMemoryRegionInfo", d.virtualMemoryRegionInfo)
      if #available(iOS 17.0, *), let r = d.exceptionReason {
        m["exceptionReason"] = [
          "composedMessage": r.composedMessage,
          "formatString": r.formatString,
          "arguments": r.arguments,
          "exceptionType": r.exceptionType,
          "className": r.className,
          "exceptionName": r.exceptionName,
        ]
      }
      return m
    }
    out["hangs"] = (p.hangDiagnostics ?? []).map { d -> [String: Any] in
      var m = common(d, tree: d.callStackTree, summary: summary)
      put(&m, "hangDurationSec", seconds(d.hangDuration))
      return m
    }
    out["cpuExceptions"] = (p.cpuExceptionDiagnostics ?? []).map { d -> [String: Any] in
      var m = common(d, tree: d.callStackTree, summary: summary)
      put(&m, "totalCpuTimeSec", seconds(d.totalCPUTime))
      put(&m, "totalSampledTimeSec", seconds(d.totalSampledTime))
      return m
    }
    out["diskWriteExceptions"] = (p.diskWriteExceptionDiagnostics ?? []).map { d -> [String: Any] in
      var m = common(d, tree: d.callStackTree, summary: summary)
      put(&m, "totalWritesBytes", finite(d.totalWritesCaused.converted(to: .bytes).value))
      return m
    }
    if #available(iOS 16.0, *) {
      out["appLaunches"] = (p.appLaunchDiagnostics ?? []).map { d -> [String: Any] in
        var m = common(d, tree: d.callStackTree, summary: summary)
        put(&m, "launchDurationSec", seconds(d.launchDuration))
        return m
      }
    }
    return out
  }

  static func metrics(_ p: MXMetricPayload) -> [String: Any] {
    var out = envelope(begin: p.timeStampBegin, end: p.timeStampEnd, raw: p.jsonRepresentation())
    out["appVersion"] = p.latestApplicationVersion
    out["multipleAppVersions"] = p.includesMultipleApplicationVersions
    if let md = p.metaData {
      out["meta"] = meta(md, appVersion: p.latestApplicationVersion)
    }
    if let exits = p.applicationExitMetrics {
      let f = exits.foregroundExitData
      out["foregroundExits"] = [
        "normal": f.cumulativeNormalAppExitCount,
        "abnormal": f.cumulativeAbnormalExitCount,
        "watchdog": f.cumulativeAppWatchdogExitCount,
        "memoryResourceLimit": f.cumulativeMemoryResourceLimitExitCount,
        "badAccess": f.cumulativeBadAccessExitCount,
        "illegalInstruction": f.cumulativeIllegalInstructionExitCount,
      ]
      let b = exits.backgroundExitData
      out["backgroundExits"] = [
        "normal": b.cumulativeNormalAppExitCount,
        "abnormal": b.cumulativeAbnormalExitCount,
        "watchdog": b.cumulativeAppWatchdogExitCount,
        "memoryResourceLimit": b.cumulativeMemoryResourceLimitExitCount,
        "badAccess": b.cumulativeBadAccessExitCount,
        "illegalInstruction": b.cumulativeIllegalInstructionExitCount,
        "memoryPressure": b.cumulativeMemoryPressureExitCount,
        "cpuResourceLimit": b.cumulativeCPUResourceLimitExitCount,
        "suspendedWithLockedFile": b.cumulativeSuspendedWithLockedFileExitCount,
        "backgroundTaskAssertionTimeout": b.cumulativeBackgroundTaskAssertionTimeoutExitCount,
      ]
    }
    if let memory = p.memoryMetrics {
      put(&out, "peakMemoryBytes", finite(memory.peakMemoryUsage.converted(to: .bytes).value))
    }
    return out
  }

  private static func envelope(begin: Date, end: Date, raw: Data) -> [String: Any] {
    [
      "receivedAt": millis(Date()),
      "begin": millis(begin),
      "end": millis(end),
      "raw": String(decoding: raw, as: UTF8.self),
    ]
  }

  private static func common(_ d: MXDiagnostic, tree: MXCallStackTree, summary: (Int) -> String?) -> [String: Any] {
    let md = meta(d.metaData, appVersion: d.applicationVersion)
    var m: [String: Any] = [
      "meta": md,
      "callStackTree": String(decoding: tree.jsonRepresentation(), as: UTF8.self),
    ]
    if let pid = md["pid"] as? Int {
      put(&m, "processStateSummary", summary(pid))
    }
    return m
  }

  private static func meta(_ md: MXMetaData, appVersion: String) -> [String: Any] {
    var m: [String: Any] = [
      "appVersion": appVersion,
      "appBuildVersion": md.applicationBuildVersion,
      "osVersion": md.osVersion,
      "deviceType": md.deviceType,
      "platformArchitecture": md.platformArchitecture,
      "regionFormat": md.regionFormat,
    ]
    if #available(iOS 17.0, *) {
      m["pid"] = Int(md.pid)
      m["isTestFlightApp"] = md.isTestFlightApp
      m["lowPowerModeEnabled"] = md.lowPowerModeEnabled
    }
    #if compiler(>=6.2)
    if #available(iOS 26.0, *) {
      put(&m, "bundleIdentifier", md.bundleIdentifier)
    }
    #endif
    return m
  }

  private static func put<T>(_ m: inout [String: Any], _ key: String, _ value: T?) {
    if let value { m[key] = value }
  }

  private static func seconds(_ m: Measurement<UnitDuration>) -> Double? {
    finite(m.converted(to: .seconds).value)
  }

  /// JSONSerialization raises an uncatchable exception for NaN and infinity.
  private static func finite(_ value: Double) -> Double? {
    value.isFinite ? value : nil
  }

  private static func millis(_ date: Date) -> Int64 {
    Int64(date.timeIntervalSince1970 * 1000)
  }
}
