import ActivityKit // AlertConfiguration.AlertSound lives here
import AlarmKit
import Foundation
import SwiftUI

/// Rise attaches no custom data to its alarms. `AlarmMetadata` is a marker
/// protocol (Codable, Hashable, Sendable), so an empty struct satisfies it.
@available(iOS 26.0, *)
struct RiseAlarmMetadata: AlarmMetadata {}

/// The iOS 26+ system-alarm engine.
///
/// This is the only iOS path that behaves like an alarm rather than a
/// notification: it **breaks through silent mode and Focus/DND**, the system
/// renders a full-screen alert, and the alarm survives force-quit and reboot.
/// The pre-26 notification burst can do none of that — a muted iPhone simply
/// stays quiet — which is why this engine exists.
///
/// Recurrence is handed to the OS rather than computed in Dart. iOS has no
/// boot-receiver equivalent, so nothing runs our code to re-arm a fired alarm;
/// a repeating alarm passed as a one-shot instant would fire once and never
/// again. `NativeAlarm.hour/minute/weekdays` carry the *pattern* for exactly
/// this, and Android keeps ignoring them. This is the one documented exception
/// to "Dart owns all scheduling."
///
/// Requires only the `NSAlarmKitUsageDescription` Info.plist string. There is
/// **no** `com.apple.developer.alarmkit` entitlement — it does not exist, and
/// adding it breaks signing with "Provisioning profile doesn't include…".
///
/// NOTE: written on Windows against Apple's documented API and never compiled.
/// Points that could not be pinned from documentation are marked
/// ⚠️ VERIFY AT BUILD — on those, the compiler is the source of truth.
@available(iOS 26.0, *)
final class AlarmKitEngine {

  private let manager = AlarmManager.shared

  /// Alarm ids are small autoincrement Int64s; AlarmKit keys on UUID. The
  /// mapping lives in `RiseAlarmIdentity` because the Stop intent needs the
  /// same one — if the two ever disagreed, Stop would open the ring screen on
  /// the wrong alarm.
  private func uuid(for id: Int64) -> UUID { RiseAlarmIdentity.uuid(for: id) }

  private static var ringNowOffset: Int64 { RiseAlarmIdentity.ringNowOffset }

  // MARK: - Authorization

  /// AlarmKit has its OWN authorization, separate from notification permission.
  /// On iOS 26+ this — not the notification switch — is what gates whether an
  /// alarm fires, so the Setup Guardian must read this one.
  var isAuthorized: Bool {
    manager.authorizationState == .authorized
  }

  var authorizationDescription: String {
    switch manager.authorizationState {
    case .notDetermined: return "notDetermined (the system prompt has never been shown)"
    case .authorized: return "authorized"
    case .denied: return "denied (the user must re-enable it in Settings)"
    @unknown default: return "unknown"
    }
  }

  func requestAuthorization() {
    Task {
      let state = try? await manager.requestAuthorization()
      NSLog("Rise[alarmkit]: authorization is now \(String(describing: state))")
    }
  }

  // MARK: - Scheduling

  /// Replaces the whole scheduled set — the same contract as the Android
  /// reconcile: whatever Dart passes becomes the complete truth.
  func reconcile(_ alarms: [NativeAlarm]) {
    Task {
      for existing in manager.alarms {
        try? await manager.cancel(id: existing.id)
      }
      var scheduled = 0
      for alarm in alarms {
        do {
          try await schedule(alarm, idOffset: 0)
          scheduled += 1
        } catch {
          NSLog("Rise[alarmkit]: FAILED to schedule alarm \(alarm.id): \(error)")
        }
      }
      NSLog("Rise[alarmkit]: reconcile — requested=\(alarms.count) scheduled=\(scheduled)")
    }
  }

  /// Missed-alarm recovery: ring ~2 s out without disturbing the scheduled set.
  func ringNow(_ alarm: NativeAlarm) {
    var immediate = alarm
    immediate.weekdays = [] // force a fixed one-shot rather than a recurrence
    immediate.fireAtEpochMs = Int64(Date().timeIntervalSince1970 * 1000) + 2000
    Task {
      do {
        try await schedule(immediate, idOffset: Self.ringNowOffset)
      } catch {
        NSLog("Rise[alarmkit]: FAILED to ring alarm \(alarm.id) now: \(error)")
      }
    }
  }

  func cancelAll() {
    RiseRingingAlarmStore.clear()
    Task {
      for alarm in manager.alarms {
        try? await manager.cancel(id: alarm.id)
      }
    }
  }

  func stopRinging(_ alarmId: Int64) {
    // The mission is done (or there was none), so the alarm is no longer owed —
    // clear the store, or getRingingAlarmId() would keep re-opening the ring
    // screen every time the app resumed.
    if RiseRingingAlarmStore.get() == alarmId { RiseRingingAlarmStore.clear() }
    // Stop both the scheduled alarm and any immediate recovery ring for it —
    // a dismissal must not leave the recovery copy sounding.
    let targets = [uuid(for: alarmId), uuid(for: alarmId &+ Self.ringNowOffset)]
    Task {
      for target in targets where manager.alarms.contains(where: { $0.id == target }) {
        try? await manager.stop(id: target)
      }
    }
  }

  /// The id of the alarm awaiting dismissal, if any.
  ///
  /// AlarmKit does not wake the app at fire time — the system draws the alert —
  /// so the app learns what is ringing by polling this, exactly as the Android
  /// RingActivity path does.
  ///
  /// The store is checked FIRST and it is the load-bearing half: by the time the
  /// app is foregrounded the user has tapped Stop, so the alarm is no longer
  /// alerting and the live poll below would answer nil. That is precisely the
  /// window in which the mission has to appear. The live poll still covers the
  /// case where the app is already open when an alarm fires.
  func ringingAlarmId() -> Int64? {
    if let stored = RiseRingingAlarmStore.get() { return stored }
    for alarm in manager.alarms where isAlerting(alarm) {
      if let raw = RiseAlarmIdentity.riseId(fromUUIDString: alarm.id.uuidString) {
        return raw
      }
    }
    return nil
  }

  // MARK: - private

  private func schedule(_ a: NativeAlarm, idOffset: Int64) async throws {
    let alarmId = uuid(for: a.id &+ idOffset)

    let schedule: Alarm.Schedule
    if a.weekdays.isEmpty {
      schedule = .fixed(Date(timeIntervalSince1970: Double(a.fireAtEpochMs) / 1000.0))
    } else {
      let time = Alarm.Schedule.Relative.Time(hour: Int(a.hour), minute: Int(a.minute))
      let days = a.weekdays.map { weekday(fromIndex: $0) }
      schedule = .relative(.init(time: time, repeats: .weekly(days)))
    }

    // ⚠️ VERIFY AT BUILD: the non-deprecated initializer is
    // `init(title:secondaryButton:secondaryButtonBehavior:)` — the system
    // supplies the Stop button now. If the compiler asks for `stopButton:`,
    // that is the deprecated form; prefer this one.
    let alert = AlarmPresentation.Alert(
      title: LocalizedStringResource(stringLiteral: a.label.isEmpty ? "Rise" : a.label),
      secondaryButton: nil,
      secondaryButtonBehavior: nil
    )
    let attributes = AlarmAttributes(
      presentation: AlarmPresentation(alert: alert),
      metadata: RiseAlarmMetadata(),
      tintColor: Color(red: 0.96, green: 0.62, blue: 0.04) // brand amber #F59E0B
    )

    // A sound name that does not resolve to a bundled file is the bug that made
    // every iOS alarm silent, so resolve first and pass `.default` otherwise.
    // ⚠️ VERIFY AT BUILD/DEVICE: `.named` has reported quirks across
    // .caf/.m4a/.mp3 on device — confirm the tone actually plays.
    let sound: AlertConfiguration.AlertSound
    if let stem = RiseSound.bundledStem(for: a.soundAsset) {
      sound = .named(stem + ".caf")
    } else {
      NSLog("Rise[alarmkit]: no bundled sound for '\(a.soundAsset)' — using the default")
      sound = .default
    }

    // The Stop button MUST carry an intent. With `stopIntent: nil` the system
    // just silences the alarm and Rise is never launched — which let a missioned
    // alarm be dismissed from the lock screen without doing the mission at all.
    // `RiseStopIntent.openAppWhenRun` is what brings the app up so the ring
    // screen (and the mission) is actually shown. See RiseAlarmIntent.swift.
    let config = AlarmManager.AlarmConfiguration(
      countdownDuration: nil,
      schedule: schedule,
      attributes: attributes,
      stopIntent: RiseStopIntent(alarmID: alarmId.uuidString),
      secondaryIntent: nil,
      sound: sound
    )
    _ = try await manager.schedule(id: alarmId, configuration: config)
  }

  /// Domain weekdays are 0=Sun…6=Sat (see the Pigeon `NativeAlarm` doc).
  private func weekday(fromIndex i: Int64) -> Locale.Weekday {
    switch i {
    case 0: return .sunday
    case 1: return .monday
    case 2: return .tuesday
    case 3: return .wednesday
    case 4: return .thursday
    case 5: return .friday
    default: return .saturday
    }
  }

  /// ⚠️ VERIFY AT BUILD: `Alarm` carries state, but the exact enum case for
  /// "alerting" could not be pinned from documentation. Matching on the
  /// description keeps this compiling whatever the case is named; if the
  /// compiler exposes a real case (e.g. `.alerting`), prefer comparing to it
  /// directly and delete this.
  private func isAlerting(_ alarm: Alarm) -> Bool {
    "\(alarm.state)".lowercased().contains("alert")
  }
}
