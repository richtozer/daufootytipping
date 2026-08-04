import Flutter
import UIKit
import UserNotifications

public final class DauAppBadgePlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "coach.interview.daufootytipping/app_badge",
      binaryMessenger: registrar.messenger()
    )
    let instance = DauAppBadgePlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
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
}
