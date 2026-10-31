import Flutter
import UIKit

// The iOS 27 SDK requires the UIScene life cycle: the app delegate owns the
// engine and registers plugins, the scene delegate shows it.
@main
@objc class AppDelegate: FlutterAppDelegate {
  lazy var engine = FlutterEngine(name: "main")

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    engine.run()
    GeneratedPluginRegistrant.register(with: engine)
    CrashLab.register(messenger: engine.binaryMessenger)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard let windowScene = scene as? UIWindowScene,
      let app = UIApplication.shared.delegate as? AppDelegate
    else { return }
    let window = UIWindow(windowScene: windowScene)
    window.rootViewController = FlutterViewController(engine: app.engine, nibName: nil, bundle: nil)
    window.makeKeyAndVisible()
    self.window = window
  }
}

/// Ways to kill or freeze the app for the example's crash lab.
enum CrashLab {
  static func register(messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: "app_diagnostics_example/crash_lab", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        switch call.method {
        case "hang":
          // Blocks the main thread: MetricKit reports an MXHangDiagnostic.
          result(nil)
          DispatchQueue.main.async { Thread.sleep(forTimeInterval: 8) }
        case "objcException":
          NSException(
            name: .invalidArgumentException,
            reason: "crash_lab: uncaught NSException from the crash lab",
            userInfo: nil
          ).raise()
        case "oom":
          // Grows until the system kills the app for its memory limit.
          DispatchQueue.global().async {
            var chunks: [UnsafeMutableRawPointer] = []
            while true {
              let chunk = malloc(64 << 20)!
              memset(chunk, 1, 64 << 20)
              chunks.append(chunk)
            }
          }
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
  }
}
