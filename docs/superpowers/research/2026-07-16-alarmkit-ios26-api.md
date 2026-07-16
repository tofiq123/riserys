# AlarmKit (iOS 26) API Reference — for Plan 2

**Date:** 2026-07-16
**Purpose:** Accurate AlarmKit API for the Rise iOS engine, since Swift can't be compiled on the Windows dev machine. Signatures marked **[confirmed]** came from Apple's documentation JSON; **[sample]** from Apple's sample article or shipped-app writeups.

**Framework fact:** AlarmKit is **iOS/iPadOS/Mac Catalyst 26.0+ only**. No watchOS/AppKit. Top-level symbols: `Alarm`, `AlarmManager`, `AlarmButton`, `AlarmPresentation`, `AlarmPresentationState`, `AlarmAttributes`, `AlarmMetadata`. Config is nested: `AlarmManager.AlarmConfiguration<Metadata>`.

## Three corrections that would have broken the code

1. **The Stop button is system-provided now.** The `AlarmPresentation.Alert(title:stopButton:secondaryButton:secondaryButtonBehavior:)` initializer is **deprecated**. Use `init(title:secondaryButton:secondaryButtonBehavior:)`.
2. **AlarmKit DOES give a dismissal callback** (the spec assumed it didn't): the `stopIntent.perform()` runs your code when the user taps Stop, and `AlarmManager.shared.alarmUpdates` (an `AsyncSequence<[Alarm], Never>`) emits on state changes while the app runs. There are **two** intents — `stopIntent` and `secondaryIntent` — both `LiveActivityIntent` (there is no `AlarmIntent`).
3. **`com.apple.developer.alarmkit` does NOT exist.** LLMs hallucinate this entitlement; adding it to `*.entitlements` causes the build error "Provisioning profile doesn't include the com.apple.developer.alarmkit entitlement." **Only** `NSAlarmKitUsageDescription` in Info.plist is required — no entitlement, no capability, no approval. (Distinct from Critical Alerts, a real approval-gated entitlement we are not using.)

## 1. Authorization [confirmed]

Info.plist: `NSAlarmKitUsageDescription` (String) — without it, scheduling fails entirely.

```swift
static let shared: AlarmManager
var authorizationState: AlarmManager.AuthorizationState   // synchronous
func requestAuthorization() async throws -> AlarmManager.AuthorizationState
enum AuthorizationState { case notDetermined, authorized, denied }
```

Authorization is also requested automatically on first `schedule`.

## 2. Scheduling [confirmed]

```swift
func schedule<Metadata>(id: Alarm.ID,                       // Alarm.ID == UUID
    configuration: AlarmManager.AlarmConfiguration<Metadata>) async throws -> Alarm
func stop(id: Alarm.ID) async throws
func cancel(id: Alarm.ID) async throws
var alarms: [Alarm]                                          // current alarms
var alarmUpdates: some AsyncSequence<[Alarm], Never>
```

`AlarmManager.AlarmConfiguration<Metadata: AlarmMetadata>` initializer:
```swift
init(countdownDuration: Alarm.CountdownDuration?,
     schedule: Alarm.Schedule?,
     attributes: AlarmAttributes<Metadata>,
     stopIntent: (any LiveActivityIntent)?,
     secondaryIntent: (any LiveActivityIntent)?,
     sound: AlertConfiguration.AlertSound)
```
Convenience factories: `.alarm(schedule:attributes:stopIntent:secondaryIntent:sound:)`, `.timer(...)`.

`Alarm.Schedule` enum — two cases:
```swift
case fixed(Date)                          // one-shot at absolute Date (ignores TZ changes)
case relative(Alarm.Schedule.Relative)    // wall-clock, TZ-aware, repeats
```
```swift
struct Relative { init(time: Time, repeats: Recurrence)
    struct Time { init(hour: Int, minute: Int) }
    enum Recurrence { case never; case weekly([Locale.Weekday]) } }
```
**Weekdays are `Locale.Weekday`** (`.monday`…`.sunday`), passed as an **array** — not a recurrence-rule object.

- One-shot at a Date: `.fixed(date)`.
- Weekly Mon/Wed/Fri 07:00: `.relative(.init(time: .init(hour:7,minute:0), repeats: .weekly([.monday,.wednesday,.friday])))`.
- Daily: `.weekly([all seven])`. Next-7:00-once: `.relative(.init(time:…, repeats: .never))`.

## 3. Presentation [confirmed]

Presentation lives inside `AlarmAttributes`, **not** on the config:
```swift
struct AlarmAttributes<Metadata: AlarmMetadata> {   // : ActivityAttributes
    init(presentation: AlarmPresentation, metadata: Metadata?, tintColor: Color) }

struct AlarmPresentation { init(alert: Alert, countdown: Countdown? = nil, paused: Paused? = nil) }
```
`AlarmPresentation.Alert` — use the non-deprecated init (system provides Stop):
```swift
init(title: LocalizedStringResource,
     secondaryButton: AlarmButton?,
     secondaryButtonBehavior: AlarmPresentation.Alert.SecondaryButtonBehavior?)
```
```swift
struct AlarmButton { init(text: LocalizedStringResource, textColor: Color, systemImageName: String) }
enum SecondaryButtonBehavior { case countdown, custom }
```
- `.countdown` → secondary button snoozes (uses `countdownDuration`); no intent needed.
- `.custom` → secondary button runs your `secondaryIntent`.

`AlarmMetadata` is a marker protocol (`Codable, Hashable, Sendable`); define an empty conforming struct if you have no data.

## 4. App Intents [confirmed protocol + sample]

Both intents conform to `LiveActivityIntent`:
```swift
struct StopIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop"
    @Parameter(title: "alarmID") var alarmID: String
    init(alarmID: String) { self.alarmID = alarmID }
    init() { self.alarmID = "" }
    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) { try await AlarmManager.shared.stop(id: id) }
        return .result()
    }
}
```
To open the app (dismiss-mission pattern): `static var openAppWhenRun = true` on the intent — launches the app to foreground even from cold. `perform()` runs in your app's process (this is the interaction hook). Intents usually live in a shared target.

## 5. Countdown / widget extension [sample, high confidence]

- A **Widget Extension (Live Activity) is required only if you schedule a `countdownDuration`** (timers / snooze). Declared via `ActivityConfiguration(for: AlarmAttributes<Meta>.self)`.
- A **plain alert-only alarm (no countdown) needs NO widget extension** — the system renders the full-screen ring UI from your `AlarmPresentation.Alert`. **[high confidence, worth a 5-min empirical check on device].**
- Plan 2 uses alert-only alarms → **no widget extension.**

## 6. Sounds [confirmed type, sample behavior]

`sound:` type is `AlertConfiguration.AlertSound` (from ActivityKit): `.default` or `.named("filename")`. Custom sound must be **local/bundled** (app bundle or `Library/Sounds`); no remote URLs. **Gotchas:** custom sounds flaky on Simulator; some `.named` bugs across `.caf/.m4a/.mp3` on device; a non-existent name falls back to default. **Test sound on a physical device.**

## 7. Hard limitations (corrected)

- **No app wake at fire time** for arbitrary code — the *system* renders the alarm. But a button tap runs the associated intent in your process, and `openAppWhenRun` launches the app.
- **Dismissal IS observable** — via `stopIntent.perform()` (reliable) and `alarmUpdates` (only while app runs).
- **Breaks silent mode + Focus/DND** — the framework's core purpose; needs authorization.
- **No documented max alarm count.** Treat "unlimited" as undocumented.
- **Survives force-quit + reboot** [dev-confirmed, high] — a system daemon holds alarms. (A locked device right after restart may limit a Live Activity UI until first unlock — affects countdown UI, not firing.)

## 8. OS / SDK / gating [confirmed]

- Runtime iOS 26.0+; build with Xcode 26 / iOS 26 SDK.
- Keep deployment target 16 and gate: `import AlarmKit` at file scope is safe; guard symbol use with `@available(iOS 26.0, *)` on types/functions and `if #available(iOS 26.0, *)` at call sites.

## 9. Entitlements [confirmed]

**None.** Only `NSAlarmKitUsageDescription`. Do **not** add `com.apple.developer.alarmkit` (does not exist). See correction #3.

## Design implications for Rise (Plan 2)

- **iOS uses AlarmKit native recurrence**, not Android's "computed next instant" model. iOS has no boot/reconcile trigger to re-arm a fired one-shot, so a repeating alarm must be `.relative(.weekly([...]))` and let the system own recurrence. → the platform contract must carry the alarm's `hour`, `minute`, `weekdays` to iOS (Android keeps ignoring them and using `fireAtEpochMs`). This is a deliberate, documented exception to "Dart owns all scheduling," justified because only the OS can reliably re-arm on iOS.
- **`stopRinging`/`getRingingAlarmId`** map cleanly: `stop(id:)` and querying `alarms` for an alerting one. The `stopIntent` is the natural dismissal hook, but writing the dismissal back to the Drift DB from a Swift App Intent is a Plan 4 concern (missions/dismissal recording); Plan 2 just rings and stops.
- **`ringNow`** (missed-alarm recovery) → schedule a `.fixed(now + ~2s)` AlarmKit alarm (26+) or an immediate notification (<26).
- **No widget extension** (alert-only alarms) → keeps signing to one target.

## Sources
Apple docs: developer.apple.com/documentation/AlarmKit (+ /alarmmanager, /alarmmanager/alarmconfiguration, /alarm/schedule-swift.enum, /alarmpresentation, /alarmattributes, /alarmbutton); BundleResources NSAlarmKitUsageDescription; "Scheduling an alarm with AlarmKit" sample. WWDC25 session 230. Dev writeups: itsuki (levelup.gitconnected), Jacob Bartlett ADHDAlarms, createwithswift, mjtsai. Entitlement myth: developer.apple.com/forums/thread/797950.
