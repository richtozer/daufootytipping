import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var appBadgeChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AppBadgeChannel") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "coach.interview.daufootytipping/app_badge",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "setCount" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let arguments = call.arguments as? [String: Any],
        let count = arguments["count"] as? Int,
        count >= 0
      else {
        result(
          FlutterError(
            code: "invalid_count",
            message: "Badge count must not be negative",
            details: nil
          )
        )
        return
      }

      if #available(iOS 16.0, *) {
        UNUserNotificationCenter.current().setBadgeCount(count) { error in
          DispatchQueue.main.async {
            result(error == nil)
          }
        }
      } else {
        UIApplication.shared.applicationIconBadgeNumber = count
        result(true)
      }
    }
    appBadgeChannel = channel
  }
}
