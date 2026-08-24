import Flutter
import UIKit
import UserNotifications

/// iOS 16+ implementation of the Pigeon `AlarmHostApi`, using local
/// notifications (there is no system-alarm API before iOS 26 / AlarmKit).
///
/// The Dart engine is platform-agnostic: it queries `capabilities()`, gets
/// `supportsSystemAlarms == false`, and therefore drives `reconcileNotifications`
/// (a "burst" of notifications from the 64-cap allocator) rather than
/// `reconcile`. When the user taps an alarm notification the app foregrounds and
/// Dart's resume-poll of `getRingingAlarmId()` shows the ring screen — the exact
/// same poll the Android RingActivity relies on.
///
/// SOUND (learned on device, 2026-08-24): the first build on a real iPhone was
/// completely silent. Two causes, both fixed here and worth not re-introducing:
///
///  1. The tone files were never in "Copy Bundle Resources", so every
///     `UNNotificationSound(named:)` named a file that did not exist. iOS then
///     delivers the notification with NO sound — it does NOT fall back to the
///     default chime, which is what the old comment here claimed. The whole
///     library now ships as `.caf` under `ios/Runner/Sounds/` and is covered by
///     a test (see `test/domain/alarm_sounds_test.dart`).
///  2. Even correctly bundled, a notification sound obeys the ringer volume and
///     the hardware mute switch, and stops after ~30 s. It cannot carry an
///     alarm on its own. The in-app player in `lib/data/ring_audio.dart` covers
///     the foreground case with an AVAudioSession `playback` category, which is
///     the only route a non-system app has to be heard on a silenced phone.
///
/// A phone that is muted and never opens the app still will not make noise.
/// Closing that gap needs AlarmKit (iOS 26+), not more work in this file.
final class AlarmHostApiImpl: NSObject, AlarmHostApi, UNUserNotificationCenterDelegate {

  private let center = UNUserNotificationCenter.current()

  /// The alarm id whose notification the user tapped, or nil. Read synchronously
  /// by `getRingingAlarmId()`; the whole iOS ring flow hangs off this.
  private var ringingAlarmId: Int64?

  /// Cached notification-authorization state. iOS only exposes it via an async
  /// callback, but the Pigeon `getPermissions()` is synchronous — so we cache it
  /// and refresh on init / after a request / on app foreground.
  private var notificationsAuthorized = false

  // Identifier scheme (prefix-based so a partial cancel can target one alarm):
  //   alarm.<alarmId>.<burstIndex>   — a ring-burst notification
  //   wakecheck.<alarmId>            — the "still up?" prompt
  //   wakecheckrefire.<alarmId>      — the re-ring if the prompt is ignored
  //   bedtime.reminder               — the single nightly wind-down reminder
  private static let alarmPrefix = "alarm."
  private static let wakeCheckPrefix = "wakecheck."
  private static let wakeCheckRefirePrefix = "wakecheckrefire."
  private static let bedtimeIdentifier = "bedtime.reminder"

  static let alarmCategoryId = "RISE_ALARM"
  static let wakeCheckCategoryId = "RISE_WAKECHECK"
  static let bedtimeCategoryId = "RISE_BEDTIME"
  static let imUpActionId = "RISE_IM_UP"

  override init() {
    super.init()
    refreshAuthorization()
  }

  /// Re-reads the notification-authorization status into the cache. Call on
  /// app foreground (see AppDelegate) so `getPermissions()` stays current.
  func refreshAuthorization() {
    center.getNotificationSettings { [weak self] settings in
      let ok = settings.authorizationStatus == .authorized
        || settings.authorizationStatus == .provisional
        || settings.authorizationStatus == .ephemeral
      // An alarm that is authorized but has alerts or sound switched off in
      // Settings looks identical to a working one from Dart's side, so name the
      // exact state here — this is the first thing to read when "the alarm
      // never fired" and nothing at all appeared on the lock screen.
      NSLog("""
        Rise[alarm]: authorization=\(Self.describe(settings.authorizationStatus)) \
        alert=\(settings.alertSetting == .enabled) \
        sound=\(settings.soundSetting == .enabled) \
        lockScreen=\(settings.lockScreenSetting == .enabled)
        """)
      // Confine the cache write to main — the callback runs on a background
      // queue and getPermissions() reads it on the platform thread.
      DispatchQueue.main.async { self?.notificationsAuthorized = ok }
    }
  }

  private static func describe(_ status: UNAuthorizationStatus) -> String {
    switch status {
    case .notDetermined: return "notDetermined (the system prompt has never been shown)"
    case .denied: return "denied (the user must re-enable it in Settings)"
    case .authorized: return "authorized"
    case .provisional: return "provisional"
    case .ephemeral: return "ephemeral"
    @unknown default: return "unknown"
    }
  }

  /// `UNUserNotificationCenter.add` without a completion handler silently
  /// discards its error, so a request rejected by the OS (unresolvable sound,
  /// bad trigger, past the 64-notification cap) looked exactly like a scheduled
  /// one. Every add goes through here so a failure is at least visible in the
  /// device log.
  private func add(_ request: UNNotificationRequest) {
    center.add(request) { error in
      if let error = error {
        NSLog("Rise[alarm]: FAILED to schedule '\(request.identifier)': \(error.localizedDescription)")
      }
    }
  }

  // MARK: - Notification content

  /// Maps the app's Flutter sound asset (e.g. "sounds/rise_sunrise.ogg") to the
  /// bundled iOS notification sound of the same base name (rise_sunrise.caf).
  ///
  /// The whole tone library is mirrored into the app bundle as IMA4 `.caf`
  /// (see `ios/Runner/Sounds/`, generated from `assets/sounds/*.ogg`). iOS only
  /// accepts Linear PCM / IMA4 / µ-law / a-law under 30 s for a notification
  /// sound — it cannot decode the `.ogg` Flutter assets Android plays, which is
  /// why a parallel `.caf` set exists at all.
  ///
  /// A name that does NOT resolve to a bundled file makes iOS deliver the
  /// notification **silently** — it does not fall back to the default chime.
  /// That is what shipped before these files were added to Copy Bundle
  /// Resources, and it is why no alarm ever made a sound. So resolve the name
  /// against the bundle here and fall back to `.default` explicitly rather than
  /// trusting the OS to do it.
  ///
  /// A voice-clip sound is an absolute file path (starts with "/"); notification
  /// sounds must be app-bundled, so a voice path can't resolve here and falls
  /// back to the default — the iOS voice-as-alarm path is served by the in-app
  /// ring player instead.
  private func sound(for asset: String) -> UNNotificationSound {
    guard let stem = RiseSound.bundledStem(for: asset) else {
      NSLog("Rise[alarm]: no bundled sound for '\(asset)' — using the default chime")
      return .default
    }
    return UNNotificationSound(named: UNNotificationSoundName(rawValue: stem + ".caf"))
  }

  // NOTE (per-alarm vibration patterns): `NativeAlarm.vibrationPattern`
  // ('gentle' | 'standard' | 'intense') is intentionally IGNORED on iOS.
  // Local notifications cannot carry a custom vibration pattern — iOS plays
  // the system's notification haptic alongside the sound and exposes no API
  // to change it (CoreHaptics only works with the app foregrounded, which an
  // alarm firing from a killed app is not). Android honors the pattern in
  // AlarmService.startVibration; here every alarm keeps today's behavior.
  private func alarmContent(label: String, soundAsset: String) -> UNMutableNotificationContent {
    let content = UNMutableNotificationContent()
    content.title = label.isEmpty ? "Rise" : label
    content.body = "Tap to stop the alarm."
    content.sound = sound(for: soundAsset)
    content.categoryIdentifier = AlarmHostApiImpl.alarmCategoryId
    if #available(iOS 15.0, *) {
      content.interruptionLevel = .timeSensitive
    }
    return content
  }

  private func triggerSeconds(fireAtEpochMs: Int64) -> TimeInterval {
    let fireAt = TimeInterval(fireAtEpochMs) / 1000.0
    let delta = fireAt - Date().timeIntervalSince1970
    return max(1, delta) // UNTimeIntervalNotificationTrigger requires > 0
  }

  // MARK: - AlarmHostApi

  func capabilities() throws -> PlatformCapabilities {
    // iOS 16–25 has no system-alarm API — always use the notification path.
    // (AlarmKit on iOS 26+ is a future upgrade.)
    return PlatformCapabilities(supportsSystemAlarms: false)
  }

  /// The iOS ring path: a full replace of the alarm-notification set. Pending
  /// wake-check notifications (a different prefix) are preserved.
  func reconcileNotifications(requests: [NotificationRequest]) throws {
    center.getPendingNotificationRequests { [weak self] pending in
      guard let self = self else { return }
      let staleAlarmIds = pending
        .map { $0.identifier }
        .filter { $0.hasPrefix(AlarmHostApiImpl.alarmPrefix) }
      if !staleAlarmIds.isEmpty {
        self.center.removePendingNotificationRequests(withIdentifiers: staleAlarmIds)
      }
      var scheduled = 0
      for req in requests {
        let seconds = self.triggerSeconds(fireAtEpochMs: req.fireAtEpochMs)
        // A request already in the past (allocator edge / clock skew) is skipped.
        if TimeInterval(req.fireAtEpochMs) / 1000.0 <= Date().timeIntervalSince1970 - 1 {
          continue
        }
        let content = self.alarmContent(label: req.label, soundAsset: req.sound)
        content.userInfo = ["alarmId": req.alarmId]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let id = "\(AlarmHostApiImpl.alarmPrefix)\(req.alarmId).\(req.burstIndex)"
        self.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        scheduled += 1
      }
      // "Asked for N, scheduled M, cleared S" is the one line that separates a
      // Dart-side scheduling bug from an iOS-side delivery one.
      NSLog("Rise[alarm]: reconcile — requested=\(requests.count) scheduled=\(scheduled) cleared=\(staleAlarmIds.count)")
      self.center.getPendingNotificationRequests { pending in
        NSLog("Rise[alarm]: pending after reconcile = \(pending.count)")
      }
    }
  }

  /// Never called on iOS (capabilities().supportsSystemAlarms == false), so the
  /// sync service uses reconcileNotifications instead. Kept as a safe no-op.
  func reconcile(alarms: [NativeAlarm]) throws {}

  /// Missed-alarm recovery: fire one alarm notification immediately. Also mark
  /// it ringing so a foreground / cold-start resume-poll of getRingingAlarmId()
  /// shows the ring screen, matching Android's ringNow -> RingActivity.
  func ringNow(alarm: NativeAlarm) throws {
    ringingAlarmId = alarm.id
    let content = alarmContent(label: alarm.label, soundAsset: alarm.soundAsset)
    content.userInfo = ["alarmId": alarm.id]
    let id = "\(AlarmHostApiImpl.alarmPrefix)\(alarm.id).0"
    add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
  }

  func cancelAll() throws {
    center.removeAllPendingNotificationRequests()
    center.removeAllDeliveredNotifications()
    ringingAlarmId = nil
  }

  func getPermissions() throws -> AlarmPermissions {
    // Only `notifications` is meaningful on iOS. The Android-only fields report
    // satisfied so the Setup Guardian never surfaces them here.
    return AlarmPermissions(
      notifications: notificationsAuthorized,
      exactAlarm: true,
      fullScreenIntent: true,
      batteryUnrestricted: true
    )
  }

  func requestNotificationPermission() throws {
    var options: UNAuthorizationOptions = [.alert, .sound, .badge]
    if #available(iOS 15.0, *) {
      // Ignored unless the Time-Sensitive Notifications entitlement is present
      // (see the compile checklist) — lets alarms pierce Focus/DND when it is.
      options.insert(.timeSensitive)
    }
    center.requestAuthorization(options: options) { [weak self] granted, _ in
      DispatchQueue.main.async { self?.notificationsAuthorized = granted }
    }
  }

  // The Android-specific settings deep-links have no iOS equivalent; open the
  // app's iOS Settings page as a harmless fallback (these are never shown, since
  // the perms above report satisfied).
  func openExactAlarmSettings() throws { openAppSettings() }
  func openBatterySettings() throws { openAppSettings() }
  func openFullScreenIntentSettings() throws { openAppSettings() }

  private func openAppSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    DispatchQueue.main.async {
      UIApplication.shared.open(url)
    }
  }

  func getRingingAlarmId() throws -> Int64? {
    return ringingAlarmId
  }

  // iOS has no single-service ring model to queue behind — each alarm is
  // its own local notification and the OS delivers them independently, so
  // there is nothing to report as "queued." Always nil.
  func getQueuedAlarmId() throws -> Int64? {
    return nil
  }

  // No ring queue to remove from (see getQueuedAlarmId). No-op.
  func removeQueuedAlarm(alarmId: Int64) throws {}

  func stopRinging(alarmId: Int64) throws {
    if ringingAlarmId == alarmId {
      ringingAlarmId = nil
    }
    // Cancel this alarm's remaining burst (pending + already delivered).
    let prefix = "\(AlarmHostApiImpl.alarmPrefix)\(alarmId)."
    center.getPendingNotificationRequests { [weak self] pending in
      let ids = pending.map { $0.identifier }.filter { $0.hasPrefix(prefix) }
      if !ids.isEmpty {
        self?.center.removePendingNotificationRequests(withIdentifiers: ids)
      }
    }
    center.getDeliveredNotifications { [weak self] delivered in
      let ids = delivered.map { $0.request.identifier }.filter { $0.hasPrefix(prefix) }
      if !ids.isEmpty {
        self?.center.removeDeliveredNotifications(withIdentifiers: ids)
      }
    }
  }

  func reconcileFinished() throws {
    // No headless engine to tear down on iOS.
  }

  func scheduleWakeCheck(alarm: NativeAlarm, checkAtEpochMs: Int64) throws {
    // 1) The "still up?" prompt at checkAt, with an "I'm up" action.
    let promptContent = UNMutableNotificationContent()
    promptContent.title = "Still up?"
    promptContent.body = "Tap \"I'm up\" so Rise doesn't ring again."
    promptContent.sound = .default
    promptContent.categoryIdentifier = AlarmHostApiImpl.wakeCheckCategoryId
    promptContent.userInfo = ["alarmId": alarm.id]
    if #available(iOS 15.0, *) { promptContent.interruptionLevel = .timeSensitive }
    let promptTrigger = UNTimeIntervalNotificationTrigger(
      timeInterval: triggerSeconds(fireAtEpochMs: checkAtEpochMs), repeats: false)
    add(UNNotificationRequest(
      identifier: "\(AlarmHostApiImpl.wakeCheckPrefix)\(alarm.id)",
      content: promptContent, trigger: promptTrigger))

    // 2) The re-ring 100s later if the prompt is ignored (an alarm notification).
    let refireContent = alarmContent(label: alarm.label, soundAsset: alarm.soundAsset)
    refireContent.userInfo = ["alarmId": alarm.id]
    let refireTrigger = UNTimeIntervalNotificationTrigger(
      timeInterval: triggerSeconds(fireAtEpochMs: checkAtEpochMs + 100_000), repeats: false)
    add(UNNotificationRequest(
      identifier: "\(AlarmHostApiImpl.wakeCheckRefirePrefix)\(alarm.id)",
      content: refireContent, trigger: refireTrigger))
  }

  func cancelWakeCheck(alarmId: Int64) throws {
    let ids = [
      "\(AlarmHostApiImpl.wakeCheckPrefix)\(alarmId)",
      "\(AlarmHostApiImpl.wakeCheckRefirePrefix)\(alarmId)",
    ]
    center.removePendingNotificationRequests(withIdentifiers: ids)
    center.removeDeliveredNotifications(withIdentifiers: ids)
  }

  /// The nightly wind-down reminder: a repeating calendar-triggered local
  /// notification at hour:minute, on its own category with the default sound.
  /// Deliberately NOT time-sensitive and NOT the alarm category — it is a
  /// gentle, zero-stakes nudge. `center.add` with the same identifier replaces
  /// any previously scheduled reminder, so a time change is a plain re-add.
  func scheduleBedtimeReminder(hour: Int64, minute: Int64, title: String, body: String) throws {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    content.categoryIdentifier = AlarmHostApiImpl.bedtimeCategoryId

    var components = DateComponents()
    components.hour = Int(hour)
    components.minute = Int(minute)
    // repeats: true → iOS re-fires it daily on its own; unlike Android there
    // is no re-arm loop to maintain, and it survives app restarts (though not
    // device restarts until the app next runs — acceptable for a reminder).
    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

    add(UNNotificationRequest(
      identifier: AlarmHostApiImpl.bedtimeIdentifier,
      content: content,
      trigger: trigger))
  }

  func cancelBedtimeReminder() throws {
    let ids = [AlarmHostApiImpl.bedtimeIdentifier]
    center.removePendingNotificationRequests(withIdentifiers: ids)
    center.removeDeliveredNotifications(withIdentifiers: ids)
  }

  // MARK: - UNUserNotificationCenterDelegate

  /// Foreground: still show the banner + play the sound (default behaviour would
  /// suppress it), so an alarm that fires while Rise is open still rings.
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .list, .sound])
    } else {
      completionHandler([.alert, .sound])
    }
  }

  /// A tap or action. An alarm tap records the ringing id (Dart's resume-poll
  /// then shows the ring screen); "I'm up" cancels the wake-check.
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let request = response.notification.request
    let alarmId = (request.content.userInfo["alarmId"] as? Int64)
      ?? (request.content.userInfo["alarmId"] as? Int).map(Int64.init)

    switch request.content.categoryIdentifier {
    case AlarmHostApiImpl.wakeCheckCategoryId:
      if response.actionIdentifier == AlarmHostApiImpl.imUpActionId, let id = alarmId {
        try? cancelWakeCheck(alarmId: id)
      }
    case AlarmHostApiImpl.bedtimeCategoryId:
      // A plain reminder tap just opens the app — it must never be mistaken
      // for a ringing alarm. (Its userInfo carries no alarmId either, so the
      // default branch would already no-op; this case makes that explicit.)
      break
    default: // RISE_ALARM (and any default tap)
      if let id = alarmId {
        ringingAlarmId = id
      }
    }
    completionHandler()
  }
}
