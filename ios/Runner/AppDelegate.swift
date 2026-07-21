import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  // Strong reference: UNUserNotificationCenter holds its delegate weakly, so the
  // AppDelegate must own the impl. (Pigeon's setUp retains the handler strongly
  // via its channel closures, but keeping this ref backstops the weak delegate.)
  private var alarmApi: AlarmHostApiImpl?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let impl = AlarmHostApiImpl()
    self.alarmApi = impl

    // Fail loudly rather than shipping a dead alarm channel: if the root
    // controller isn't a FlutterViewController, every Pigeon call from Dart
    // would silently no-op. (For this UIMainStoryboardFile=Main template the
    // window/controller are set before didFinishLaunching, so this holds.)
    if let controller = window?.rootViewController as? FlutterViewController {
      AlarmHostApiSetup.setUp(binaryMessenger: controller.binaryMessenger, api: impl)
    } else {
      assertionFailure("Rise: root controller is not a FlutterViewController — the alarm channel was not set up")
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

    // Bedtime reminder: a plain tap opens the app; no inline actions. Its own
    // category keeps it visually and behaviorally distinct from alarms.
    let bedtime = UNNotificationCategory(
      identifier: AlarmHostApiImpl.bedtimeCategoryId,
      actions: [],
      intentIdentifiers: [],
      options: []
    )

    UNUserNotificationCenter.current().setNotificationCategories([alarm, wakeCheck, bedtime])
  }
}
