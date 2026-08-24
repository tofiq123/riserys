import AlarmKit
import AppIntents
import Foundation

/// Where the "which alarm is ringing" answer survives between AlarmKit's system
/// alert and the Flutter app.
///
/// AlarmKit does not wake the app when an alarm fires — the system draws the
/// alert — so the app's only route to the ring screen is `getRingingAlarmId()`.
/// Once the user taps Stop the alarm is no longer *alerting*, so polling
/// `AlarmManager.alarms` would answer nil a moment later and the mission would
/// never appear. The Stop intent records the id here first.
///
/// `UserDefaults` rather than an in-memory static because Stop can launch the
/// app from cold: the intent may run in a process that has only just started,
/// and Dart may poll either side of it.
enum RiseRingingAlarmStore {
  private static let key = "rise.ringingAlarmId"

  static func set(_ alarmId: Int64) {
    UserDefaults.standard.set(NSNumber(value: alarmId), forKey: key)
  }

  /// The alarm awaiting dismissal, or nil. Survives app relaunch by design — a
  /// mission the user walked away from is still owed when they come back.
  static func get() -> Int64? {
    (UserDefaults.standard.object(forKey: key) as? NSNumber)?.int64Value
  }

  static func clear() {
    UserDefaults.standard.removeObject(forKey: key)
  }
}

/// The action behind AlarmKit's Stop button.
///
/// This is the "dismiss-mission pattern": `openAppWhenRun` brings Rise to the
/// foreground — **even from a cold launch on a locked phone** — so the ring
/// screen, and with it the mission, actually gets shown. Without an intent here
/// the system simply silences the alarm and the app is never involved, which is
/// how a missioned alarm could be dismissed from the lock screen without doing
/// the mission at all.
///
/// Stopping the AlarmKit alarm is not the same as dismissing the Rise alarm.
/// This only ends the *system* alert; the alarm stays "ringing" as far as the
/// app is concerned (the id above), the in-app player keeps the tone going
/// through the mute switch (`lib/data/ring_audio.dart`), and only completing
/// the mission calls `stopRinging` and clears it.
///
/// NOTE: written on Windows and never compiled. ⚠️ VERIFY AT BUILD — see the
/// compile checklist; `LiveActivityIntent` + `openAppWhenRun` is the documented
/// shape, but the launch-from-cold behaviour needs confirming on hardware.
@available(iOS 26.0, *)
struct RiseStopIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "Stop"

  /// The whole point: bring the app up so the mission can be enforced.
  static var openAppWhenRun: Bool = true

  @Parameter(title: "alarmID")
  var alarmID: String

  init(alarmID: String) { self.alarmID = alarmID }
  init() { self.alarmID = "" }

  func perform() async throws -> some IntentResult {
    // Record BEFORE stopping: once stopped, nothing else can say which alarm
    // this was, and the ring screen would open on nothing.
    if let riseId = RiseAlarmIdentity.riseId(fromUUIDString: alarmID) {
      RiseRingingAlarmStore.set(riseId)
    }
    // `stop` is a synchronous throws API (not async).
    if let uuid = UUID(uuidString: alarmID) {
      try? AlarmManager.shared.stop(id: uuid)
    }
    return .result()
  }
}

/// The Int64 alarm id ⇄ UUID mapping, shared by the engine and the Stop intent
/// so the two can never drift apart.
enum RiseAlarmIdentity {
  /// Keeps an immediate recovery ring's UUID clear of any real alarm's.
  static let ringNowOffset: Int64 = 0x1000_0000_0000

  static func uuid(for id: Int64) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012llx", id))!
  }

  /// The app-facing alarm id for a scheduled UUID, normalising a recovery ring
  /// back to the real alarm so the ring screen opens the right record.
  static func riseId(fromUUIDString s: String) -> Int64? {
    guard let uuid = UUID(uuidString: s) else { return nil }
    let hex = uuid.uuidString.replacingOccurrences(of: "-", with: "").suffix(12)
    guard let raw = Int64(hex, radix: 16) else { return nil }
    return raw >= ringNowOffset ? raw &- ringNowOffset : raw
  }
}
