# iOS engine — Mac / Codemagic compile-and-fix checklist

The iOS alarm engine (`ios/Runner/AlarmHostApiImpl.swift` + `AppDelegate.swift`) was authored on Windows against the generated Pigeon protocol + Apple's UserNotifications API, but **could not be compiled here**. This is the punch-list to get it building + running on a Mac (or a Codemagic macOS build). The Dart side is complete and already tested on this machine.

## 0. Prerequisites
- A Mac with Xcode (or a Codemagic iOS workflow), and — to run on a real iPhone or TestFlight — an **Apple Developer account** ($99/yr) for signing.
- `flutter pub get` then `cd ios && pod install` (installs the Flutter + Firebase pods; Firebase is optional at runtime, guarded like on Android).

## 1. ⭐ Add the new Swift file to the Runner target (THE critical step)
`AlarmHostApiImpl.swift` was created on disk but is **not yet referenced by `Runner.xcodeproj`** (editing the `.pbxproj` blind from Windows is unsafe). Until it's in the target it won't compile — the app will fail to link `AlarmHostApiSetup`.
- In Xcode: **File → Add Files to "Runner"…** → select `ios/Runner/AlarmHostApiImpl.swift` → ensure **"Runner" target is checked** → Add. (Or drag it into the Runner group in the Project Navigator and tick the Runner target.)

## 2. Confirm the alarm sound is a resolvable bundle resource
`UNNotificationSound(named: "default_alarm.wav")` resolves the file from the app bundle root (or `Library/Sounds/`).
- Select `ios/Runner/Sounds/default_alarm.wav` in Xcode → File Inspector → confirm **Target Membership: Runner** is checked (so it's in "Copy Bundle Resources").
- If it's inside a **folder reference** (blue folder) the runtime name would be `Sounds/default_alarm.wav`; simplest is to have it copy to the bundle root so `"default_alarm.wav"` resolves. If the sound doesn't play, this is the first thing to check (iOS silently falls back to the default sound when the name doesn't resolve).

## 3. ⭐ Wire the Time-Sensitive Notifications entitlement (matters for waking during sleep)
`content.interruptionLevel = .timeSensitive` + requesting the `.timeSensitive` auth option let alarms **pierce a Sleep/Do-Not-Disturb Focus** — the exact scenario an alarm app needs. Without the entitlement iOS silently downgrades the level, so an alarm can be suppressed while the user sleeps.
- The entitlements file already exists: **`ios/Runner/Runner.entitlements`** (key `com.apple.developer.usernotifications.time-sensitive`).
- In Xcode: Runner target → **Signing & Capabilities → + Capability → Time Sensitive Notifications** (this references the file), OR set **Build Settings → Code Signing Entitlements = `Runner/Runner.entitlements`**. Your Apple Developer account must have the capability enabled for the App ID.
- Without this the app still builds and rings; it's just suppressible by Focus.

## 3b. 64-notification cap vs. wake-checks (verify no silent drops)
iOS keeps only the 64 soonest **pending** notifications. The Dart allocator budgets the alarm burst, but `scheduleWakeCheck` adds 2 more (preserved across reconcile). If the allocator ever uses the full 64 while a wake-check is pending, iOS silently drops the furthest-out ones. On device, exercise many alarms **plus** an active wake-check and confirm nothing vanishes. If it does, lower the allocator's effective cap (in `lib/domain/notification_budget.dart`) to reserve ~2–4 slots for wake-checks.

## 4. Build
- `flutter build ios --debug` (or `flutter build ipa` on Codemagic). Expect the **first build to surface Swift errors** — this code has never seen a compiler. Likely spots to fix:
  - The `window?.rootViewController as? FlutterViewController` cast in `AppDelegate` — if `AlarmHostApiSetup.setUp` never runs (channel calls hang), the root controller wasn't a `FlutterViewController` at launch; move the setUp into a `plugin`-style registration or after the window is keyed.
  - `userInfo["alarmId"]` decoding: the Pigeon codec sends `Int64`; the `as? Int64 ?? (as? Int)` fallback covers the `NSNumber` bridging, but verify on-device that `getRingingAlarmId()` returns the tapped id.
  - Any `throws`/optional/availability mismatch the compiler flags — mechanical.

## 5. On-device smoke test (the real verification)
1. Launch, grant the notification permission (Profile → the app requests it; or first alarm arm).
2. Create an alarm ~1–2 min out. Background the app / lock the phone.
3. At the time, a **notification fires with the alarm sound** (and repeats via the burst). Confirm it shows on the lock screen.
4. **Tap** the notification → the app opens to the **ring screen** with the mission → complete it → dismiss. Confirm the remaining burst notifications stop (no more sounds).
5. Edit/disable the alarm → confirm its pending notifications are cleared (a reconcile ran).
6. Wake-check (if enabled): after dismiss, the "Still up?" prompt fires; "I'm up" cancels; ignoring it re-rings after ~100s.

## 6. Known iOS limitations (by design, not bugs)
- No full-screen ring and no ring-until-dismissed: iOS plays the burst's ≤30 s sounds and stops if the user never taps. The mission is only enforced once they open the app.
- The 64-pending-notification cap limits how many future alarm occurrences are armed at once (the Dart allocator handles this; distant alarms arm as nearer ones pass).
- True system alarms need **AlarmKit (iOS 26+)** — a future upgrade; `capabilities()` currently reports `supportsSystemAlarms: false` for all iOS versions.

## 7. If pigeon is regenerated
`dart run pigeon --input pigeons/alarm_api.dart` regenerates `AlarmApi.g.swift`; the impl conforms to the current protocol. (Regenerating on Windows only changed line endings — the protocol is unchanged.)
