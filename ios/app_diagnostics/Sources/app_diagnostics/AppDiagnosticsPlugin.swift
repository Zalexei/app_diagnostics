import Flutter
import UIKit

/// iOS side: MetricKit diagnostics and daily metrics, kept by MetricKitStore.
public class AppDiagnosticsPlugin: NSObject, FlutterPlugin, IosDiagnosticsHostApi {
  private let store = MetricKitStore.shared

  public static func register(with registrar: FlutterPluginRegistrar) {
    MetricKitStore.shared.start()
    let plugin = AppDiagnosticsPlugin()
    IosDiagnosticsHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: plugin)
    ReportsArrivedStreamHandler.register(with: registrar.messenger(), streamHandler: ReportsStream())
  }

  func getSupport() throws -> IosSupportMessage {
    #if targetEnvironment(simulator)
    let isSimulator = true
    #else
    let isSimulator = false
    #endif
    let info = ProcessInfo.processInfo
    func atLeast(_ major: Int) -> Bool {
      info.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: major, minorVersion: 0, patchVersion: 0))
    }
    return IosSupportMessage(
      systemVersion: UIDevice.current.systemVersion,
      isSimulator: isSimulator,
      diagnostics: atLeast(14),
      immediateDelivery: atLeast(15),
      appLaunchDiagnostics: atLeast(16),
      extendedMetadata: atLeast(17)
    )
  }

  func getReports(kind: Int64) throws -> [String] {
    store.reports(try parse(kind), onlyNew: false)
  }

  func takeNewReports(kind: Int64) throws -> [String] {
    store.reports(try parse(kind), onlyNew: true)
  }

  func clearReports() throws {
    store.clear()
  }

  func setProcessStateSummary(summary: FlutterStandardTypedData?) throws -> Bool {
    store.setSummary(summary?.data)
  }

  private func parse(_ kind: Int64) throws -> MetricKitStore.Kind {
    guard let k = MetricKitStore.Kind(rawValue: Int(kind)) else {
      throw PigeonError(code: "invalid-kind", message: "Unknown report kind \(kind)", details: nil)
    }
    return k
  }
}

/// Tells Dart the kind of every report stored while it listens, and on
/// listen the kinds that already have reports takeNew has not returned.
private final class ReportsStream: ReportsArrivedStreamHandler {
  private var observer: NSObjectProtocol?

  override func onListen(withArguments arguments: Any?, sink: PigeonEventSink<Int64>) {
    onCancel(withArguments: nil)
    observer = NotificationCenter.default.addObserver(
      forName: MetricKitStore.reportsArrived, object: nil, queue: .main
    ) { note in
      if let kind = note.userInfo?["kind"] as? Int { sink.success(Int64(kind)) }
    }
    for kind in [MetricKitStore.Kind.diagnostic, .metric] where MetricKitStore.shared.hasNew(kind) {
      sink.success(Int64(kind.rawValue))
    }
  }

  override func onCancel(withArguments arguments: Any?) {
    if let observer { NotificationCenter.default.removeObserver(observer) }
    observer = nil
  }
}
