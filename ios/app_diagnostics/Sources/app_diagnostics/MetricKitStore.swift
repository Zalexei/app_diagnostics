import Foundation
import MetricKit

/// Keeps MetricKit reports on disk until Dart reads them. MetricKit hands each
/// payload over once, usually before Dart runs, so the plugin subscribes when it
/// registers and stores every payload as JSON (see MetricKitJSON).
///
/// Layout under Application Support/app_diagnostics (excluded from backups):
/// reports/<seq>-<d|m>.json (the seq is also the report's "id"), state.json
/// (next seq, last returned seq per kind), summaries.json (process state
/// summaries of recent pids).
final class MetricKitStore {
  static let shared = MetricKitStore()
  static let reportsArrived = Notification.Name("io.github.zalexei.app_diagnostics.reportsArrived")

  enum Kind: Int {
    case diagnostic = 0
    case metric = 1

    var suffix: String { self == .diagnostic ? "d" : "m" }
    /// Oldest reports beyond this count are deleted.
    var limit: Int { self == .diagnostic ? 50 : 30 }
  }

  private struct State: Codable {
    var nextSeq = 1
    var lastDiagnostic = 0
    var lastMetric = 0

    func lastTaken(_ kind: Kind) -> Int {
      kind == .diagnostic ? lastDiagnostic : lastMetric
    }

    mutating func setLastTaken(_ kind: Kind, _ seq: Int) {
      if kind == .diagnostic { lastDiagnostic = seq } else { lastMetric = seq }
    }
  }

  private struct Summary: Codable {
    var at: Int64
    var base64: String
  }

  private static let maxSummaries = 50

  private let queue = DispatchQueue(label: "io.github.zalexei.app_diagnostics.store")
  private let root: URL
  private var subscriber: NSObject?

  private init() {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    root = base.appendingPathComponent("app_diagnostics", isDirectory: true)
  }

  private var reportsDir: URL { root.appendingPathComponent("reports", isDirectory: true) }
  private var stateURL: URL { root.appendingPathComponent("state.json") }
  private var summariesURL: URL { root.appendingPathComponent("summaries.json") }

  /// Subscribes to MetricKit once per process, even with several engines.
  /// Main thread only.
  func start() {
    guard subscriber == nil else { return }
    if #available(iOS 14.0, *) {
      let s = Subscriber(store: self)
      subscriber = s
      MXMetricManager.shared.add(s)
    }
  }

  func save(_ report: [String: Any], kind: Kind) {
    let saved: Bool = queue.sync {
      ensureRoot()
      var state = loadState()
      // Never reuse a number, even if state.json was lost.
      let newest = (files(.diagnostic) + files(.metric)).map(\.seq).max() ?? 0
      let seq = max(state.nextSeq, newest + 1)
      var document = report
      document["id"] = seq
      // data(withJSONObject:) raises an uncatchable exception for invalid input.
      guard JSONSerialization.isValidJSONObject(document),
        let data = try? JSONSerialization.data(withJSONObject: document)
      else {
        NSLog("app_diagnostics: dropping a MetricKit report that is not valid JSON")
        return false
      }
      let url = reportsDir.appendingPathComponent("\(seq)-\(kind.suffix).json")
      do {
        try data.write(to: url, options: .atomic)
      } catch {
        // For example before the first unlock after a reboot (file protection).
        NSLog("app_diagnostics: cannot store a MetricKit report: \(error)")
        return false
      }
      state.nextSeq = seq + 1
      save(state)
      for old in files(kind).dropLast(kind.limit) {
        try? FileManager.default.removeItem(at: old.url)
      }
      return true
    }
    guard saved else { return }
    DispatchQueue.main.async {
      NotificationCenter.default.post(name: Self.reportsArrived, object: nil, userInfo: ["kind": kind.rawValue])
    }
  }

  /// Stored reports of [kind], oldest first. With [onlyNew], skips reports an
  /// earlier call already returned and moves the marker past the ones read.
  func reports(_ kind: Kind, onlyNew: Bool) -> [String] {
    queue.sync {
      var state = loadState()
      var out: [String] = []
      var lastRead: Int?
      for file in files(kind) where !onlyNew || file.seq > state.lastTaken(kind) {
        do {
          out.append(try String(contentsOf: file.url, encoding: .utf8))
          lastRead = file.seq
        } catch {
          NSLog("app_diagnostics: cannot read \(file.url.lastPathComponent): \(error)")
        }
      }
      if onlyNew, let lastRead {
        state.setLastTaken(kind, lastRead)
        save(state)
      }
      return out
    }
  }

  /// Whether [kind] has reports that takeNew has not returned yet.
  func hasNew(_ kind: Kind) -> Bool {
    queue.sync {
      guard let newest = files(kind).last?.seq else { return false }
      return newest > loadState().lastTaken(kind)
    }
  }

  /// Deletes the reports; sequence numbers keep growing.
  func clear() {
    queue.sync { _ = try? FileManager.default.removeItem(at: reportsDir) }
  }

  /// Remembers [summary] for the current pid; nil forgets it.
  func setSummary(_ summary: Data?) -> Bool {
    queue.sync {
      ensureRoot()
      var all = loadSummaries()
      let pid = String(ProcessInfo.processInfo.processIdentifier)
      if let summary {
        all[pid] = Summary(at: Int64(Date().timeIntervalSince1970 * 1000), base64: summary.base64EncodedString())
      } else {
        all[pid] = nil
      }
      for key in all.sorted(by: { $0.value.at > $1.value.at }).dropFirst(Self.maxSummaries).map(\.key) {
        all[key] = nil
      }
      guard let data = try? JSONEncoder().encode(all) else { return false }
      return (try? data.write(to: summariesURL, options: .atomic)) != nil
    }
  }

  /// Base64 summary that the process [pid] left, if any.
  func summary(pid: Int) -> String? {
    queue.sync { loadSummaries()[String(pid)]?.base64 }
  }

  // Everything below runs on [queue].

  private func ensureRoot() {
    let fm = FileManager.default
    guard !fm.fileExists(atPath: reportsDir.path) else { return }
    try? fm.createDirectory(at: reportsDir, withIntermediateDirectories: true)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    var url = root
    try? url.setResourceValues(values)
  }

  private func loadState() -> State {
    guard let data = try? Data(contentsOf: stateURL) else { return State() }
    return (try? JSONDecoder().decode(State.self, from: data)) ?? State()
  }

  private func save(_ state: State) {
    if let data = try? JSONEncoder().encode(state) {
      try? data.write(to: stateURL, options: .atomic)
    }
  }

  private func loadSummaries() -> [String: Summary] {
    guard let data = try? Data(contentsOf: summariesURL) else { return [:] }
    return (try? JSONDecoder().decode([String: Summary].self, from: data)) ?? [:]
  }

  /// Report files of [kind] by sequence number, oldest first.
  private func files(_ kind: Kind) -> [(seq: Int, url: URL)] {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: reportsDir.path)) ?? []
    return names.compactMap { name -> (seq: Int, url: URL)? in
      let parts = name.replacingOccurrences(of: ".json", with: "").split(separator: "-")
      guard parts.count == 2, parts[1] == kind.suffix, let seq = Int(parts[0]) else { return nil }
      return (seq, reportsDir.appendingPathComponent(name))
    }.sorted { $0.seq < $1.seq }
  }
}

@available(iOS 14.0, *)
private final class Subscriber: NSObject, MXMetricManagerSubscriber {
  private let store: MetricKitStore

  init(store: MetricKitStore) {
    self.store = store
  }

  func didReceive(_ payloads: [MXDiagnosticPayload]) {
    for payload in payloads {
      store.save(MetricKitJSON.diagnostics(payload, summary: store.summary(pid:)), kind: .diagnostic)
    }
  }

  func didReceive(_ payloads: [MXMetricPayload]) {
    for payload in payloads {
      store.save(MetricKitJSON.metrics(payload), kind: .metric)
    }
  }
}
