# Rise — iOS alarm engine (design)

**Date:** 2026-07-20
**Status:** Drafted. Builds on Plan 2 Groups A+B (iOS target 16, bundled sound, NotificationRequest value type, 64-cap allocator, extended Pigeon contract, capability-branched sync — all merged) and the merged Android engine. This is **Plan 2 Groups C+D**: the iOS-native `AlarmHostApi` implementation.

## Goal

Make Rise ring on iPhone (iOS 16+), reusing the existing cross-platform Dart engine. **The entire Dart side is already done and platform-agnostic** — `AlarmSyncService` branches on `capabilities().supportsSystemAlarms`, the burst allocator produces `NotificationRequest`s, and `main.dart` already polls `getRingingAlarmId()` on resume/cold-start. So this phase is **Swift-only**: implement the Pigeon `AlarmHostApi` protocol with `UNUserNotificationCenter`, and wire it in `AppDelegate`.

## The honest iOS constraint

iOS has **no** equivalent to Android's `AlarmManager.setAlarmClock` + full-screen intent + foreground service. An app cannot run code at a scheduled time or take over the screen. The only scheduled-alert primitive is **local notifications** (`UNNotificationRequest`), which:
- iOS keeps only the **64 soonest** pending → hence the Dart 64-cap allocator.
- play a **≤30 s** custom sound per notification → the "burst" (several notifications ~30 s apart) simulates a longer ring.
- show a banner / lock-screen notification, **not** a full-screen ring. The mission UI appears only when the user **taps** the notification and the app opens.

Consequence, stated plainly: on iOS a wake-up is a **burst of loud notifications**; if the user never taps, the sounds play and stop (no enforced mission). Tapping opens the app to the existing `RingScreen` (mission and all). This is the ceiling of what iOS 16–25 allows; **AlarmKit (iOS 26+)** would give true system alarms and is a future upgrade (the contract + `NSAlarmKitUsageDescription` already anticipate it).

## Architecture (Swift-only)

**`ios/Runner/AlarmHostApiImpl.swift`** — a class conforming to the generated `AlarmHostApi` protocol **and** `UNUserNotificationCenterDelegate`:
- `capabilities()` → `PlatformCapabilities(supportsSystemAlarms: false)` (notification path everywhere on iOS 16+; AlarmKit deferred).
- `reconcileNotifications(requests)` → **full replace**: remove all pending alarm notifications, then schedule each `NotificationRequest` as a `UNNotificationRequest` with a `UNTimeIntervalNotificationTrigger` (`max(1, fireAt − now)` seconds), the mapped bundled sound, category `RISE_ALARM`, identifier `alarm.<alarmId>.<burstIndex>`, and `userInfo["alarmId"]`. Past-due requests (≤ now) are skipped.
- `reconcile(alarms)` → no-op (never called on iOS since `supportsSystemAlarms == false`; documented).
- `ringNow(alarm)` → an **immediate** alarm notification (nil trigger) for missed-alarm recovery.
- `cancelAll()` → remove all pending + delivered `RISE_ALARM` notifications; clear the ringing id.
- `getPermissions()` → `notifications` = real `UNUserNotificationCenter` authorization; the Android-only fields (`exactAlarm`, `fullScreenIntent`, `batteryUnrestricted`) report **true** so the Setup Guardian never surfaces them on iOS.
- `requestNotificationPermission()` → `requestAuthorization([.alert, .sound, .badge])`.
- `openExactAlarmSettings/openBatterySettings/openFullScreenIntentSettings()` → open the app's iOS Settings page (`UIApplication.openSettingsURLString`); harmless fallbacks (they're never shown, since the perms report satisfied).
- `getRingingAlarmId()` → the alarm id set by the notification-tap delegate, or nil. **This is the whole ring flow**: tap → set id → Dart's resume-poll shows `RingScreen`.
- `stopRinging(alarmId)` → if it matches the ringing id, clear it; cancel that alarm's remaining burst (`alarm.<alarmId>.*`) pending + delivered.
- `reconcileFinished()` → no-op (no headless engine to tear down on iOS).
- `scheduleWakeCheck(alarm, checkAtEpochMs)` → a `RISE_WAKECHECK` "Still up?" notification at `checkAt` (with an "I'm up" action) + a re-fire alarm notification at `checkAt + 100 s`. `cancelWakeCheck(alarmId)` removes both.

**`UNUserNotificationCenterDelegate`** (same class):
- `willPresent` → foreground: present with `.banner, .sound` so a notification arriving while the app is open still rings.
- `didReceive` → on a `RISE_ALARM` tap: set the ringing id (Dart shows `RingScreen` on the resume-poll). On the `RISE_WAKECHECK` "I'm up" action: `cancelWakeCheck`. Always call the completion handler.

**`ios/Runner/AppDelegate.swift`** — after `GeneratedPluginRegistrant.register`: get the `FlutterViewController`'s `binaryMessenger`, construct the impl, `AlarmHostApiSetup.setUp(binaryMessenger:, api: impl)`, hold a **strong reference** to it (else it deallocs), set it as `UNUserNotificationCenter.current().delegate`, and register the `RISE_ALARM` + `RISE_WAKECHECK` categories.

**Sound mapping:** the app's `soundAsset` (e.g. `sounds/default_alarm.mp3`) is a Flutter asset path; iOS notification sounds must be bundled `.wav/.aiff/.caf`. v1 has one bundled sound — `ios/Runner/Sounds/default_alarm.wav`. The Swift maps any request sound to `default_alarm.wav` (the only bundled iOS sound), falling back to `UNNotificationSound.default` if the file isn't found.

## Verification

- **Dart:** unchanged → `flutter test` + `flutter analyze` stay green (the whole diff is under `ios/`).
- **Pigeon:** the generated `AlarmApi.g.swift` is regenerated with pigeon 26.3.4 so the impl conforms to the current contract.
- **Swift: review-verified only.** It cannot be compiled on this Windows machine. It is written against the exact generated protocol + Apple's `UNUserNotificationCenter` API and reviewed for API-correctness. **It ships needing one compile-and-fix pass on a Mac or a Codemagic macOS build** — see the checklist below.

## Mac / Codemagic compile checklist (`docs/superpowers/reliability/2026-07-20-ios-compile-checklist.md`)

The exact steps to compile-verify + run on a Mac/Codemagic, the likely-manual Xcode bits I can't do from Windows (target membership of `AlarmHostApiImpl.swift` in the pbxproj; confirming `default_alarm.wav` is in "Copy Bundle Resources" at the bundle root for `UNNotificationSound`; `pod install`; notification capability), and the on-device smoke test (schedule an alarm → notification fires with sound → tap → ring screen → mission → dismiss cancels the burst).

## Out of scope (this phase)

AlarmKit (iOS 26+ true system alarms), iOS push/APNs (the 5d nudge receive side on iOS), Critical Alerts (needs Apple entitlement approval), per-sound iOS bundles (v1 has one), the Xcode signing/provisioning (user does on the Mac).
