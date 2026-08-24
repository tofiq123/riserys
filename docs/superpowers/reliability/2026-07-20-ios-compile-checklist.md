# iOS engine — Mac / Codemagic compile-and-fix checklist

The iOS alarm engine (`ios/Runner/AlarmHostApiImpl.swift` + `AppDelegate.swift`) was authored on Windows against the generated Pigeon protocol + Apple's UserNotifications API, but **could not be compiled here**. This is the punch-list to get it building + running on a Mac (or a Codemagic macOS build). The Dart side is complete and already tested on this machine.

## 0. Prerequisites
- A Mac with Xcode (or a Codemagic iOS workflow), and — to run on a real iPhone or TestFlight — an **Apple Developer account** ($99/yr) for signing.
- `flutter pub get` then `cd ios && pod install` (installs the Flutter + Firebase pods; Firebase is optional at runtime, guarded like on Android).

## 1. ⭐ Add the new Swift file to the Runner target (THE critical step)
`AlarmHostApiImpl.swift` was created on disk but is **not yet referenced by `Runner.xcodeproj`** (editing the `.pbxproj` blind from Windows is unsafe). Until it's in the target it won't compile — the app will fail to link `AlarmHostApiSetup`.
- In Xcode: **File → Add Files to "Runner"…** → select `ios/Runner/AlarmHostApiImpl.swift` → ensure **"Runner" target is checked** → Add. (Or drag it into the Runner group in the Project Navigator and tick the Runner target.)

## 2. ~~Confirm the alarm sound is a resolvable bundle resource~~ — DONE 2026-08-24

**This step was skipped, and it is what made the first device build silent.** Kept here because the reasoning was wrong in a way worth remembering.

The original note claimed "iOS silently falls back to the default sound when the name doesn't resolve." That is false. A `UNNotificationSound(named:)` whose file is not in the bundle makes iOS deliver the notification with **no sound at all**. Nothing in the app or the logs said so — it simply never made a noise.

What is now in place:
- The whole tone library is converted to IMA4 `.caf` (mono, 22.05 kHz, all under Apple's 30 s ceiling) in `ios/Runner/Sounds/`, generated from `assets/sounds/*.ogg` — iOS cannot decode `.ogg` for a notification sound, which is why a parallel set has to exist.
- All 59 files are in the Runner target's **Copy Bundle Resources** phase, copied to the bundle root so a bare `"rise_klaxon.caf"` resolves.
- `sound(for:)` now checks `Bundle.main.url(forResource:withExtension:)` and falls back to `.default` *explicitly* rather than trusting the OS to.
- `test/domain/alarm_sounds_test.dart` fails if a catalog tone ever ships without its `.caf` and `.m4a` twins.

**Still true and not fixable here:** a notification sound obeys the ringer volume and the hardware mute switch. A muted iPhone stays quiet unless the app is open (see `lib/data/ring_audio.dart`, which uses an AVAudioSession `playback` category to sound through the mute switch in the foreground). A muted phone that never opens the app needs AlarmKit on iOS 26+.

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

## 8. New since 2026-08-05 (ring queue + 9-bug-fix session) — none of this has ever compiled on iOS either

- **Two new Pigeon methods, both hand-written stubs, never compiled**: `getQueuedAlarmId()` and `removeQueuedAlarm(alarmId:)` in `AlarmHostApiImpl.swift`, added for the Android-only overlapping-ring queue. Both are trivial no-ops (`return nil` / empty body) — iOS never has anything to report as queued since AlarmKit/the notification burst has no single-service ring to clobber. Low risk, but verify they compile and satisfy the regenerated protocol like anything else in section 7.

- **⭐ `permission_handler` is a new dependency (pinned `^11.3.1` — see pubspec.yaml comment on why not 13.x) — needs a fresh `pod install`, and specifically verify the steps mission on iOS.** The Android motivation was that `ACTIVITY_RECOGNITION` was declared but never requested at runtime. On iOS, Core Motion already auto-prompts on `CMPedometer`'s first actual use (no separate request needed) — that's what the pedometer plugin's own behavior relied on before this change. Requesting `Permission.activityRecognition` *up front*, before anything touches Core Motion, is untested on this exact flow: confirm on-device that (a) the system prompt still appears normally, and (b) a fresh/undetermined authorization status is not misread as "denied" and sent straight to the slide-to-wake fallback (see `defaultRequestActivityRecognition` / `_requestPermissionThenListen` in `lib/ui/missions/steps_mission.dart`) when the real answer is just "not asked yet." If this fires wrong, the steps mission would silently regress on iOS instead of getting fixed.

- **⭐ Camera preview aspect-ratio fix (`eyes_mission.dart` / `photo_mission.dart`) — verify the swap direction on iOS.** Both missions used to render `CameraPreview` in a fixed square box with no `AspectRatio`/`BoxFit`, stretching the feed (a general Flutter `RenderAspectRatio`-under-tight-constraints bug, not Android-specific). The fix wraps it in a `FittedBox` sized to `CameraController.value.previewSize`, with width/height swapped — reasoned from Android's Camera2 behavior, where `previewSize` is always reported in the sensor's native (landscape) orientation regardless of device orientation. AVFoundation's reported preview dimensions may already account for orientation differently on iOS; if the preview looks squished in the *other* axis (or rotated) after this fix, the swap in `_cameraPreview()` is the first thing to check — it may need to be conditional on platform, or removed entirely for iOS.

- **Firebase-init race fix (`firebase_ready.dart`) is pure Dart — applies to iOS's push path too, in principle.** `main.dart`'s deferred-Firebase-init-vs-first-frame race isn't Android-specific, so the fix (awaiting `firebaseReady` before `FirebaseMessaging` calls) should hold on iOS as well. But iOS push remains fundamentally unconfigured regardless (`ios/Runner/GoogleService-Info.plist` does not exist) — there is nothing to actually test here until that's set up as its own separate step; don't spend time chasing nudges on iOS before then.

- **Everything else from today's session (snoozed-time-clears-on-edit, Home's clock digits, the cheer optimistic-update, the memory-mission timing/feedback) is pure Dart/Riverpod/Flutter UI with no platform channel involved** — no iOS-specific risk, should just work identically once the app compiles at all.
