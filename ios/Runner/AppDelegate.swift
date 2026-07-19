import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  // Strong reference: the message-channel handler and the notification-center
  // delegate are both held weakly, so the AppDelegate must own the impl.
  private var alarmApi: AlarmHostApiImpl?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let impl = AlarmHostApiImpl()
    self.alarmApi = impl

    if let controller = window?.rootViewController as? FlutterViewController {
      AlarmHostApiSetup.setUp(binaryMessenger: controller.binaryMessenger, api: impl)
    }

    UNUserNotificationCenter.current().delegate = impl
    registerNotificationCategories()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Re-read notification authorization each time the app foregrounds so the
  /// cached value behind `getPermissions()` stays current (the Setup Guardian
  /// re-polls on resume).
  override func applicationDidBecomeActive(_ application: UIApplication) {
    alarmApi?.refreshAuthorization()
    super.applicationDidBecomeActive(application)
  }

  private func registerNotificationCategories() {
    // Alarm: a plain tap opens the app to the ring screen (no inline actions).
    let alarm = UNNotificationCategory(
      identifier: AlarmHostApiImpl.alarmCategoryId,
      actions: [],
      intentIdentifiers: [],
      options: []
    )

    // Wake-check: an "I'm up" action cancels the pending re-ring.
    let imUp = UNNotificationAction(
      identifier: AlarmHostApiImpl.imUpActionId,
      title: "I'm up",
      options: [.foreground]
    )
    let wakeCheck = UNNotificationCategory(
      identifier: AlarmHostApiImpl.wakeCheckCategoryId,
      actions: [imUp],
      intentIdentifiers: [],
      options: []
    )

    UNUserNotificationCenter.current().setNotificationCategories([alarm, wakeCheck])
  }
}
