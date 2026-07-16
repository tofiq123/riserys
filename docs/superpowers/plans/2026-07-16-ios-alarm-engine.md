# Rise Plan 2: iOS Alarm Engine — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Rise's alarms ring reliably on iPhone, using AlarmKit on iOS 26+ (a system alarm that breaks through silent mode and Focus) and an engineered local-notification fallback on iOS 16–25, verified on physical hardware via Codemagic + TestFlight.

**Architecture:** The shared Dart domain layer from Plan 1 (ScheduleMath, reconcile, AlarmRepository, AlarmSyncService) is reused. Plan 2 adds one pure-Dart piece (a notification-budget allocator, the only part testable on Windows), extends the platform seam so the sync service can ask the platform what it supports and hand it either system alarms or a notification burst, and implements the Swift side of the Pigeon `AlarmHostApi`: an `AlarmKitEngine` (iOS 26+) and a `NotificationEngine` (iOS 16–25), selected at runtime by `@available`. iOS has no boot-receiver equivalent, so the platform holds scheduled alarms/notifications across reboot itself — the Android headless-reconcile path has no iOS counterpart.

**One deliberate architectural divergence — iOS delegates recurrence to the OS.** On Android, Dart owns *all* scheduling: it computes the single next fire-instant and re-arms on every reconcile trigger (boot, edit, clock change). iOS has **no reliable background re-arm trigger** — nothing runs our code on boot — so a repeating alarm passed as a one-shot instant would fire once and never again. AlarmKit and `UNCalendarNotificationTrigger` both support native recurrence, so on iOS we must hand the platform the alarm's *pattern* (`hour`, `minute`, `weekdays`) and let the OS own the repeat. The Pigeon `NativeAlarm` therefore gains `hour`, `minute`, `weekdays`; **Android ignores them and keeps using `fireAtEpochMs` (Plan 1 code path untouched)**; iOS builds `.relative(.weekly([…]))` / `.fixed(Date)` from them. This is a conscious, documented exception to "Dart owns all scheduling," justified because only the OS can re-arm reliably on iOS. `fireAtEpochMs` still rides along for the `ringNow` immediate path and as the notification-burst base time on the pre-26 fallback.

**Tech Stack:** Flutter 3.35.1 / Dart 3.9.0 (shared) · Swift 5.9+ / iOS 16 deployment target · AlarmKit (iOS 26 SDK) · UserNotifications · Pigeon (existing `AlarmApi.g.swift`) · Codemagic (cloud macOS CI) · App Store Connect / TestFlight

**Verification reality — read before starting:** The development machine is Windows with **no Mac**. Swift cannot be compiled or run locally. Every Swift task's real verification is a **Codemagic cloud build**, and behavioral verification is **TestFlight on a physical iPhone**. Both are gated on an **Apple Developer Program membership ($99/yr)** and an iPhone the user must supply. The pure-Dart tasks (allocator, sync-service branching) are fully testable on Windows now; the Swift tasks are written carefully and verified in the cloud/on-device phase at the end (Tasks 12–14). Do not claim a Swift task "works" from reading code — say it compiles when Codemagic is green, and rings when TestFlight proves it.

**Out of scope (later plans / deferred):** the real design-system UI (Plan 3 — Plan 2 reuses the throwaway `DevHomePage`/`DevRingPage`); missions, snooze, wake-up-check (Plan 4); all social/backend (Plans 5–6); AlarmKit countdown Live Activities / widget extension (deferred — the core "ring reliably" goal does not need a countdown, and a widget extension doubles the signing/target surface); Critical Alerts entitlement (spec §4: routinely refused, never a dependency).

## Global Constraints

Copied verbatim from `docs/superpowers/specs/2026-07-15-rise-alarm-app-design.md` §4 and the Plan 1 result. Every task's requirements implicitly include this section.

- **iOS deployment target 16.** The scaffold currently sets 13.0 — Task 1 raises it. AlarmKit code is gated behind `if #available(iOS 26.0, *)` so the iOS-16 floor still builds and runs.
- **AlarmKit is the iOS 26+ path**; the notification stack is the iOS 16–25 fallback and a belt-and-braces layer. AlarmKit's three constraints drive the design: it does **not** wake the app at ring time; it plays **bundled/local sounds only**; and it gives **no callback when the user dismisses**, so every AlarmKit alarm is paired with the Wake-Up Check (Plan 4) and the app learns "what is ringing" only by polling `getRingingAlarmId()`.
- **AlarmKit needs NO entitlement — only the `NSAlarmKitUsageDescription` Info.plist string.** There is **no `com.apple.developer.alarmkit` entitlement**; it is a hallucination that, if added to `*.entitlements`, causes a hard signing/build failure ("Provisioning profile doesn't include the com.apple.developer.alarmkit entitlement"). Never add it. (Full API details: `docs/superpowers/research/2026-07-16-alarmkit-ios26-api.md`.)
- **AlarmKit's Stop button is system-provided** — use `AlarmPresentation.Alert(title:secondaryButton:secondaryButtonBehavior:)` (the `stopButton:` initializer is deprecated). Recurrence is `Alarm.Schedule.Relative.Recurrence.weekly([Locale.Weekday])` — an array of Foundation weekdays, not a rule object.
- **AlarmKit does give a dismissal signal** (correcting the spec): `stopIntent.perform()` runs in-app on Stop, and `AlarmManager.shared.alarmUpdates` emits while the app runs. Plan 2 uses this only to answer `getRingingAlarmId`/`stopRinging`; writing dismissal back to the DB (one-shot disable, recovery suppression) is Plan 4.
- **Critical Alerts: not planned for.** Do not add its entitlement (`com.apple.developer.usernotifications.critical-alerts`, a different, approval-gated thing) or make any feature depend on it.
- **No overnight keep-alive.** The pre-26 fallback accepts honest degradation (force-quit + silent switch → notifications that vibrate only) rather than draining the battery to stay alive.
- **Notification sounds are capped at 30 seconds**; a longer file is silently replaced by the default. **iOS caps pending local notifications at 64 per app** — the allocator's hard budget.
- **A bundled default sound ships in the binary** (`default_alarm` — the Android build already carries `res/raw/default_alarm.wav`; iOS needs its own copy in the app bundle). The fallback chain never depends on a downloaded or user file.
- **Bundle id `com.riseapp.rise`** (already set in the Xcode project). Permanent after App Store publication.
- **The local database is the source of truth; no alarm path touches the network.** (Shared, from Plan 1.)
- **Reconcile is a full replace; missed-alarm recovery uses `ringNow`, never `reconcile`.** (Shared contract, from Plan 1.)
- **Launch gate (Task 15): the iOS reliability protocol passes on a physical iPhone.** Mirrors Plan 1's Android gate.

---

## File structure

**New pure-Dart (testable on Windows):**
- `lib/domain/notification_request.dart` — the value type for one scheduled local notification.
- `lib/domain/notification_budget.dart` — `allocateNotifications(...)`, the 64-cap burst allocator.
- Extends `lib/data/alarm_sync_service.dart` — `AlarmPlatform` gains `capabilities()` and `reconcileNotifications(...)`; `reconcileNow` branches on capability.

**Pigeon contract (regenerated — one codegen, Android no-ops the iOS-only methods):**
- `pigeons/alarm_api.dart` — adds `PlatformCapabilities`, `capabilities()`, `NotificationRequest`, `reconcileNotifications(...)`.
- `android/.../AlarmHostApiImpl.kt` — adds the two no-op/trivial methods (Android reports `supportsSystemAlarms = true`).

**New Swift (verified via Codemagic/device):**
- `ios/Runner/Alarm/AlarmHostApiImpl.swift` — implements the Pigeon protocol; owns version selection.
- `ios/Runner/Alarm/AlarmEngine.swift` — the protocol both engines conform to.
- `ios/Runner/Alarm/AlarmKitEngine.swift` — iOS 26+ AlarmKit path.
- `ios/Runner/Alarm/NotificationEngine.swift` — iOS 16–25 UserNotifications path.
- `ios/Runner/Alarm/RiseAlarmIntent.swift` — App Intent behind the AlarmKit alert's buttons.
- `ios/Runner/AppDelegate.swift` — registers the impl; wires the notification delegate.
- `ios/Runner/Info.plist` — `NSAlarmKitUsageDescription`, notification/audio background modes.
- `ios/Runner/Sounds/default_alarm.caf` — bundled default alarm sound (≤30 s).

**CI / build:**
- `codemagic.yaml` — Flutter iOS build → sign → TestFlight.

---

## Task group A — pure-Dart notification-budget allocator (fully testable on Windows)

This is the one part of Plan 2 that runs and is verified entirely on the Windows dev machine, exactly like Plan 1's `ScheduleMath`. It is written first so the trickiest logic (dividing a hard 64-notification budget across alarms) is proven before any un-testable Swift is written.

### Task 1: Raise the iOS deployment target and bundle the default sound

**Files:**
- Modify: `ios/Runner.xcodeproj/project.pbxproj` (all `IPHONEOS_DEPLOYMENT_TARGET`)
- Modify: `ios/Podfile` (platform line)
- Create: `ios/Runner/Sounds/default_alarm.caf`
- Modify: `ios/Runner/Info.plist`

**Interfaces:**
- Consumes: nothing.
- Produces: an iOS project targeting 16.0 with a bundled `default_alarm.caf` and the AlarmKit usage string in Info.plist. No Dart or Swift logic yet.

> This task changes only build configuration and an asset. It cannot be compiled on Windows; its verification is that the files contain the exact expected values (checked by grep) and that Task 13's first Codemagic build accepts them. That is the correct verification for a config-only task here.

- [ ] **Step 1: Raise the deployment target in the Xcode project**

In `ios/Runner.xcodeproj/project.pbxproj`, replace every `IPHONEOS_DEPLOYMENT_TARGET = 13.0;` with `IPHONEOS_DEPLOYMENT_TARGET = 16.0;`.

```bash
cd "C:/Users/ASUS/Desktop/startuping/rise"
sed -i 's/IPHONEOS_DEPLOYMENT_TARGET = 13.0;/IPHONEOS_DEPLOYMENT_TARGET = 16.0;/g' ios/Runner.xcodeproj/project.pbxproj
grep -c "IPHONEOS_DEPLOYMENT_TARGET = 16.0;" ios/Runner.xcodeproj/project.pbxproj
```
Expected: a count ≥ 2 (Debug + Release; RunnerTests may add more), and zero remaining `13.0`.

- [ ] **Step 2: Set the Podfile platform**

In `ios/Podfile`, ensure the platform line reads exactly:

```ruby
platform :ios, '16.0'
```

If the line is commented (`# platform :ios, '12.0'`), uncomment and set it. Verify:

```bash
grep -n "platform :ios" ios/Podfile
```
Expected: `platform :ios, '16.0'` uncommented.

- [ ] **Step 3: Add the bundled default sound**

iOS alarm/notification sounds must be a CAF/AIFF/WAV in the app bundle, ≤ 30 s. Generate a 520 Hz placeholder CAF (Plan 3 replaces it with the designed melodic asset), reusing the same tone rationale as Android (`res/raw/default_alarm.wav`).

```bash
mkdir -p ios/Runner/Sounds
python -c "
import math, struct, wave
# 520 Hz square wave, 25 s, 44.1 kHz mono, 16-bit. Written as WAV; Xcode/afconvert
# accepts WAV for notification sounds. 25 s stays under the 30 s cap with margin.
rate, secs, freq = 44100, 25, 520
w = wave.open('ios/Runner/Sounds/default_alarm.wav','w')
w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate)
w.writeframes(b''.join(struct.pack('<h', 12000 if math.sin(2*math.pi*freq*t/rate)>0 else -12000) for t in range(rate*secs)))
w.close(); print('wrote ios/Runner/Sounds/default_alarm.wav')
"
```

> The file is named `default_alarm.wav`. iOS notification `UNNotificationSound(named:)` accepts a `.wav` in the bundle. Task 13 adds it to the Xcode "Copy Bundle Resources" build phase via the Codemagic build (Flutter's Xcode project references files added under `ios/Runner/`; the plan's Task 6 Info.plist + build settings ensure it is copied). If Codemagic reports the sound missing from the bundle, add it to the Runner target's resources in the project.pbxproj.

- [ ] **Step 4: Add the AlarmKit usage string and notification/audio modes to Info.plist**

In `ios/Runner/Info.plist`, inside the top-level `<dict>`, add:

```xml
	<key>NSAlarmKitUsageDescription</key>
	<string>Rise uses alarms to wake you at the times you set, even when your phone is silent.</string>
	<key>UIBackgroundModes</key>
	<array>
		<string>audio</string>
	</array>
```

> `NSAlarmKitUsageDescription` is required for AlarmKit authorization (confirmed in §Research). The `audio` background mode lets the fallback keep playing alarm audio when the app is foregrounded/backgrounded at ring time; it is NOT a keep-alive (spec forbids that) — it only applies while the app is actually running audio. Verify:

```bash
grep -c "NSAlarmKitUsageDescription" ios/Runner/Info.plist
```
Expected: `1`.

- [ ] **Step 5: Commit**

```bash
git add ios/Runner.xcodeproj/project.pbxproj ios/Podfile ios/Runner/Sounds/ ios/Runner/Info.plist
git commit -m "build(ios): target iOS 16, bundle default alarm sound, add AlarmKit usage string"
```

---

### Task 2: NotificationRequest value type

**Files:**
- Create: `lib/domain/notification_request.dart`
- Test: `test/domain/notification_request_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `class NotificationRequest` with `int alarmId`, `int fireAtEpochMs` (absolute UTC ms), `String label`, `String sound`, `int burstIndex` (0 = the alarm's first/primary notification), `int burstTotal`; value equality; `const` constructor.

- [ ] **Step 1: Write the failing test**

Create `test/domain/notification_request_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/notification_request.dart';

void main() {
  test('holds its fields', () {
    const r = NotificationRequest(
      alarmId: 3,
      fireAtEpochMs: 1784276400000,
      label: 'Run',
      sound: 'default_alarm.wav',
      burstIndex: 0,
      burstTotal: 16,
    );
    expect(r.alarmId, 3);
    expect(r.fireAtEpochMs, 1784276400000);
    expect(r.label, 'Run');
    expect(r.sound, 'default_alarm.wav');
    expect(r.burstIndex, 0);
    expect(r.burstTotal, 16);
  });

  test('is the primary notification when burstIndex is 0', () {
    const primary = NotificationRequest(
        alarmId: 1, fireAtEpochMs: 0, label: 'a', sound: 's', burstIndex: 0, burstTotal: 4);
    const followUp = NotificationRequest(
        alarmId: 1, fireAtEpochMs: 0, label: 'a', sound: 's', burstIndex: 1, burstTotal: 4);
    expect(primary.isPrimary, isTrue);
    expect(followUp.isPrimary, isFalse);
  });

  test('value equality', () {
    const a = NotificationRequest(
        alarmId: 1, fireAtEpochMs: 10, label: 'x', sound: 's', burstIndex: 0, burstTotal: 1);
    const b = NotificationRequest(
        alarmId: 1, fireAtEpochMs: 10, label: 'x', sound: 's', burstIndex: 0, burstTotal: 1);
    const c = NotificationRequest(
        alarmId: 1, fireAtEpochMs: 20, label: 'x', sound: 's', burstIndex: 0, burstTotal: 1);
    expect(a, equals(b));
    expect(a, isNot(equals(c)));
    expect(a.hashCode, b.hashCode);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/domain/notification_request_test.dart
```
Expected: FAIL — `notification_request.dart` not found.

- [ ] **Step 3: Write the implementation**

Create `lib/domain/notification_request.dart`:

```dart
/// One scheduled local notification in an alarm's ring "burst".
///
/// The iOS 16–25 fallback simulates a ringing alarm by scheduling several
/// notifications 30 s apart, each with a ≤30 s sound. [burstIndex] 0 is the
/// alarm's first notification; later indices are the follow-ups that keep the
/// sound going. [fireAtEpochMs] is absolute UTC — all wall-clock/DST reasoning
/// already happened upstream in ScheduleMath.
class NotificationRequest {
  const NotificationRequest({
    required this.alarmId,
    required this.fireAtEpochMs,
    required this.label,
    required this.sound,
    required this.burstIndex,
    required this.burstTotal,
  });

  final int alarmId;
  final int fireAtEpochMs;
  final String label;
  final String sound;
  final int burstIndex;
  final int burstTotal;

  bool get isPrimary => burstIndex == 0;

  @override
  bool operator ==(Object other) =>
      other is NotificationRequest &&
      other.alarmId == alarmId &&
      other.fireAtEpochMs == fireAtEpochMs &&
      other.label == label &&
      other.sound == sound &&
      other.burstIndex == burstIndex &&
      other.burstTotal == burstTotal;

  @override
  int get hashCode =>
      Object.hash(alarmId, fireAtEpochMs, label, sound, burstIndex, burstTotal);

  @override
  String toString() =>
      'NotificationRequest(alarm: $alarmId, at: $fireAtEpochMs, $burstIndex/$burstTotal)';
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
flutter test test/domain/notification_request_test.dart
```
Expected: PASS — 3 tests green.

- [ ] **Step 5: Commit**

```bash
git add lib/domain/notification_request.dart test/domain/notification_request_test.dart
git commit -m "feat: add NotificationRequest value type for the iOS notification stack"
```

---

### Task 3: The 64-notification budget allocator

The heart of the iOS fallback and the one piece of genuinely tricky iOS logic that runs on Windows. Given the upcoming alarms and the hard 64-notification iOS cap, it decides how many notifications each alarm gets (soonest alarms get fuller bursts; every representable alarm fires at least once) and expands them into concrete fire-times.

**Files:**
- Create: `lib/domain/notification_budget.dart`
- Test: `test/domain/notification_budget_test.dart`

**Interfaces:**
- Consumes: `ScheduledOccurrence` (Plan 1, `lib/domain/scheduled_occurrence.dart`: `int alarmId`, `DateTime fireAt` [UTC], `String label`, `String soundAsset`, `bool vibrate`), `NotificationRequest` (Task 2).
- Produces:
  - `const int kIosNotificationCap = 64;`
  - `List<NotificationRequest> allocateNotifications({required List<ScheduledOccurrence> occurrences, required DateTime now, int cap = kIosNotificationCap, int perAlarmMax = 16, Duration spacing = const Duration(seconds: 30)})` — sorted by `fireAtEpochMs`; total length ≤ `cap`; future occurrences only.
  - `int droppedAlarmCount({required List<ScheduledOccurrence> occurrences, required DateTime now, int cap = kIosNotificationCap})` — how many future alarms got zero notifications because the cap was exhausted (for logging; silent truncation is forbidden by the spec).

- [ ] **Step 1: Write the failing test**

Create `test/domain/notification_budget_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/notification_budget.dart';
import 'package:rise/domain/notification_request.dart';
import 'package:rise/domain/scheduled_occurrence.dart';

void main() {
  final now = DateTime.utc(2026, 7, 16, 12, 0, 0);

  ScheduledOccurrence occ(int id, int minutesFromNow) => ScheduledOccurrence(
        alarmId: id,
        fireAt: now.add(Duration(minutes: minutesFromNow)),
        label: 'Alarm $id',
        soundAsset: 'default_alarm.wav',
        vibrate: true,
      );

  group('single alarm', () {
    test('gets a full burst of perAlarmMax notifications', () {
      final out = allocateNotifications(occurrences: [occ(1, 5)], now: now);
      expect(out, hasLength(16));
      expect(out.every((n) => n.alarmId == 1), isTrue);
      expect(out.map((n) => n.burstIndex).toList(), List.generate(16, (i) => i));
      expect(out.every((n) => n.burstTotal == 16), isTrue);
    });

    test('spaces the burst 30 s apart starting at the fire time', () {
      final out = allocateNotifications(occurrences: [occ(1, 5)], now: now);
      final base = now.add(const Duration(minutes: 5)).millisecondsSinceEpoch;
      expect(out[0].fireAtEpochMs, base);
      expect(out[1].fireAtEpochMs, base + 30000);
      expect(out[15].fireAtEpochMs, base + 15 * 30000);
    });
  });

  group('budget distribution', () {
    test('five alarms stay within the 64 cap, soonest fullest', () {
      final out = allocateNotifications(
        occurrences: [occ(1, 5), occ(2, 60), occ(3, 120), occ(4, 180), occ(5, 240)],
        now: now,
      );
      expect(out.length, lessThanOrEqualTo(64));
      int countFor(int id) => out.where((n) => n.alarmId == id).length;
      // Every alarm fires at least once; soonest is non-increasing.
      for (final id in [1, 2, 3, 4, 5]) {
        expect(countFor(id), greaterThanOrEqualTo(1), reason: 'alarm $id must fire');
      }
      expect(countFor(1), 16);
      expect(countFor(1) >= countFor(2), isTrue);
      expect(countFor(2) >= countFor(3), isTrue);
    });

    test('never exceeds the cap even with many alarms', () {
      final many = List.generate(20, (i) => occ(i + 1, (i + 1) * 10));
      final out = allocateNotifications(occurrences: many, now: now);
      expect(out.length, lessThanOrEqualTo(64));
    });

    test('when alarms exceed the cap, only the soonest cap alarms fire', () {
      final many = List.generate(70, (i) => occ(i + 1, i + 1));
      final out = allocateNotifications(occurrences: many, now: now);
      expect(out.length, lessThanOrEqualTo(64));
      final firingIds = out.map((n) => n.alarmId).toSet();
      expect(firingIds, hasLength(64));
      // The soonest 64 (ids 1..64) fire; the farthest 6 (65..70) are dropped.
      expect(firingIds.contains(1), isTrue);
      expect(firingIds.contains(70), isFalse);
      expect(droppedAlarmCount(occurrences: many, now: now), 6);
    });
  });

  group('filtering and ordering', () {
    test('ignores past occurrences', () {
      final out = allocateNotifications(occurrences: [occ(1, -5)], now: now);
      expect(out, isEmpty);
    });

    test('no alarms yields no notifications', () {
      expect(allocateNotifications(occurrences: const [], now: now), isEmpty);
    });

    test('output is sorted by fire time', () {
      final out = allocateNotifications(
        occurrences: [occ(1, 5), occ(2, 60)],
        now: now,
      );
      for (var i = 1; i < out.length; i++) {
        expect(out[i].fireAtEpochMs, greaterThanOrEqualTo(out[i - 1].fireAtEpochMs));
      }
    });

    test('carries the alarm sound and label', () {
      final out = allocateNotifications(
        occurrences: [
          ScheduledOccurrence(
            alarmId: 9,
            fireAt: now.add(const Duration(minutes: 5)),
            label: 'Gym',
            soundAsset: 'birdsong.wav',
            vibrate: true,
          )
        ],
        now: now,
      );
      expect(out.first.label, 'Gym');
      expect(out.first.sound, 'birdsong.wav');
    });

    test('respects a reduced cap (other notification types reserve slots)', () {
      final out = allocateNotifications(occurrences: [occ(1, 5)], now: now, cap: 4);
      expect(out, hasLength(4));
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/domain/notification_budget_test.dart
```
Expected: FAIL — `notification_budget.dart` not found.

- [ ] **Step 3: Write the implementation**

Create `lib/domain/notification_budget.dart`:

```dart
import 'notification_request.dart';
import 'scheduled_occurrence.dart';

/// iOS allows at most this many pending local notifications per app. Every
/// alarm's ring "burst" is drawn from this shared budget, so other notification
/// types (bedtime reminders, wake-up checks — Plan 4) must pass a reduced [cap].
const int kIosNotificationCap = 64;

/// Future occurrences, soonest first. Shared by both public functions so the
/// allocation and the drop-count agree exactly.
List<ScheduledOccurrence> _futureSorted(
    List<ScheduledOccurrence> occurrences, DateTime now) {
  final nowMs = now.millisecondsSinceEpoch;
  final future = occurrences
      .where((o) => o.fireAt.millisecondsSinceEpoch > nowMs)
      .toList()
    ..sort((a, b) => a.fireAt.compareTo(b.fireAt));
  return future;
}

/// Per-alarm notification counts, soonest-first, under [cap].
///
/// Rule: give every alarm 1 (a floor, so each fires at least once), as long as
/// there is room; then distribute the remaining budget soonest-first, topping
/// each alarm up toward [perAlarmMax], until the budget is spent. When there
/// are more alarms than the cap, only the soonest [cap] alarms get a slot.
List<int> _counts(List<ScheduledOccurrence> future, int cap, int perAlarmMax) {
  final n = future.length;
  if (n == 0 || cap <= 0) return const [];

  final serviced = n <= cap ? n : cap; // alarms that get at least one slot
  final counts = List<int>.filled(serviced, 1);
  var remaining = cap - serviced;

  for (var i = 0; i < serviced && remaining > 0; i++) {
    final topUp = (perAlarmMax - 1) <= remaining ? (perAlarmMax - 1) : remaining;
    counts[i] += topUp;
    remaining -= topUp;
  }
  return counts;
}

/// The concrete notifications to schedule for the iOS fallback, sorted by fire
/// time, never more than [cap] in total.
List<NotificationRequest> allocateNotifications({
  required List<ScheduledOccurrence> occurrences,
  required DateTime now,
  int cap = kIosNotificationCap,
  int perAlarmMax = 16,
  Duration spacing = const Duration(seconds: 30),
}) {
  final future = _futureSorted(occurrences, now);
  final counts = _counts(future, cap, perAlarmMax);

  final out = <NotificationRequest>[];
  for (var i = 0; i < counts.length; i++) {
    final occ = future[i];
    final total = counts[i];
    final base = occ.fireAt.millisecondsSinceEpoch;
    for (var b = 0; b < total; b++) {
      out.add(NotificationRequest(
        alarmId: occ.alarmId,
        fireAtEpochMs: base + b * spacing.inMilliseconds,
        label: occ.label,
        sound: occ.soundAsset,
        burstIndex: b,
        burstTotal: total,
      ));
    }
  }

  out.sort((a, b) => a.fireAtEpochMs.compareTo(b.fireAtEpochMs));
  return out;
}

/// How many future alarms got zero notifications because the cap was exhausted.
/// Callers log this — the spec forbids silently dropping alarms.
int droppedAlarmCount({
  required List<ScheduledOccurrence> occurrences,
  required DateTime now,
  int cap = kIosNotificationCap,
}) {
  final n = _futureSorted(occurrences, now).length;
  return n > cap ? n - cap : 0;
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
flutter test test/domain/notification_budget_test.dart
```
Expected: PASS — all groups green.

> If "soonest fullest" fails: the top-up loop must run in soonest-first order over `counts` (index 0 = soonest). Do not sort `counts`. If the cap test fails, check that `serviced = min(n, cap)` and that the floor of 1-per-alarm is subtracted from the budget before top-ups.

- [ ] **Step 5: Run the whole suite**

```bash
flutter test
```
Expected: PASS — Plan 1's 63 tests plus the new allocator tests.

- [ ] **Step 6: Commit**

```bash
git add lib/domain/notification_budget.dart test/domain/notification_budget_test.dart
git commit -m "feat: add 64-cap iOS notification-budget allocator"
```

---

## Task group B — platform contract + Dart branching (testable on Windows)

The sync service must be able to ask the platform whether it supports system alarms and, when it does not (iOS 16–25), hand it a notification burst instead. This extends the shared Pigeon contract with two methods and one type; Android no-ops the notification path and reports that it does support system alarms.

### Task 4: Extend the Pigeon contract with capabilities + notifications

**Files:**
- Modify: `pigeons/alarm_api.dart`
- Regenerated: `lib/data/native/alarm_api.g.dart`, `android/app/src/main/kotlin/com/riseapp/rise/AlarmApi.g.kt`, `ios/Runner/AlarmApi.g.swift`
- Modify: `android/app/src/main/kotlin/com/riseapp/rise/AlarmHostApiImpl.kt`

**Interfaces:**
- Consumes: nothing (contract definition).
- Produces (Pigeon-generated, consumed by Tasks 5 and the Swift tasks):
  - `NativeAlarm` gains `int hour`, `int minute`, `List<int> weekdays` (0=Sun…6=Sat, empty = one-shot) — the recurrence pattern iOS AlarmKit needs. Android ignores them.
  - `class PlatformCapabilities { bool supportsSystemAlarms; }`
  - `class NotificationRequest { int alarmId; int fireAtEpochMs; String label; String sound; int burstIndex; int burstTotal; }` (the Pigeon wire type; distinct from the domain `NotificationRequest` in Task 2)
  - `AlarmHostApi.capabilities() -> PlatformCapabilities`
  - `AlarmHostApi.reconcileNotifications(List<NotificationRequest> requests)`
  - `ScheduledOccurrence` (domain) gains `int hour`, `int minute`, `Set<int> weekdays` with defaults, populated by `desiredOccurrences` from the alarm.

- [ ] **Step 1: Add the recurrence fields to `NativeAlarm`**

In `pigeons/alarm_api.dart`, add three fields to `NativeAlarm` (both the constructor and the field declarations):

```dart
class NativeAlarm {
  NativeAlarm({
    required this.id,
    required this.fireAtEpochMs,
    required this.label,
    required this.soundAsset,
    required this.vibrate,
    required this.hour,
    required this.minute,
    required this.weekdays,
  });

  int id;
  int fireAtEpochMs;
  String label;
  String soundAsset;
  bool vibrate;

  /// Recurrence pattern, for platforms that own recurrence natively (iOS
  /// AlarmKit / UNCalendar). [weekdays] uses 0=Sun…6=Sat; empty = one-shot.
  /// Android ignores these and schedules the single [fireAtEpochMs] instant.
  int hour;
  int minute;
  List<int> weekdays;
}
```

- [ ] **Step 2: Add the capability + notification types and methods**

In `pigeons/alarm_api.dart`, add these two classes after `AlarmPermissions` (before `@HostApi()`):

```dart
/// What a platform's alarm engine can do. iOS 16–25 has no system-alarm API,
/// so the sync service falls back to a notification burst there.
class PlatformCapabilities {
  PlatformCapabilities({required this.supportsSystemAlarms});

  /// True when the platform can schedule true system alarms (Android
  /// AlarmManager always; iOS only on 26+ via AlarmKit). False on iOS 16–25,
  /// where [AlarmHostApi.reconcileNotifications] is used instead.
  bool supportsSystemAlarms;
}

/// One scheduled local notification in the iOS 16–25 fallback burst. The Dart
/// budget allocator produces these; only the iOS notification engine consumes
/// them. Android reports [PlatformCapabilities.supportsSystemAlarms] true and
/// never receives these.
class NotificationRequest {
  NotificationRequest({
    required this.alarmId,
    required this.fireAtEpochMs,
    required this.label,
    required this.sound,
    required this.burstIndex,
    required this.burstTotal,
  });

  int alarmId;
  int fireAtEpochMs;
  String label;
  String sound;
  int burstIndex;
  int burstTotal;
}
```

Add these two methods inside `abstract class AlarmHostApi`, after `reconcileFinished()`:

```dart
  /// What this platform's alarm engine supports. Queried by the sync service
  /// to choose between system alarms and the notification-burst fallback.
  PlatformCapabilities capabilities();

  /// Replaces the platform's entire scheduled notification set (the iOS 16–25
  /// fallback). A full replace, like [reconcile]. No-op on Android.
  void reconcileNotifications(List<NotificationRequest> requests);
```

- [ ] **Step 3: Regenerate all three outputs**

```bash
cd "C:/Users/ASUS/Desktop/startuping/rise"
dart run pigeon --input pigeons/alarm_api.dart
```
Expected: no output; the three `.g` files update. Confirm the new symbols exist:

```bash
grep -l "reconcileNotifications" lib/data/native/alarm_api.g.dart android/app/src/main/kotlin/com/riseapp/rise/AlarmApi.g.kt ios/Runner/AlarmApi.g.swift
```
Expected: all three paths listed.

- [ ] **Step 4: Carry the recurrence pattern through the domain layer**

The regenerated `NativeAlarm` now requires `hour`, `minute`, `weekdays`, so `_toNative` (which builds it) needs those — sourced from `ScheduledOccurrence`, which needs them too. Add them with defaults so Plan 1's existing tests (which construct `ScheduledOccurrence` without them) keep compiling and passing.

In `lib/domain/scheduled_occurrence.dart`, add three fields to the constructor and class, and include them in `==`/`hashCode`:

```dart
  const ScheduledOccurrence({
    required this.alarmId,
    required this.fireAt,
    required this.label,
    required this.soundAsset,
    required this.vibrate,
    this.hour = 0,
    this.minute = 0,
    this.weekdays = const {},
  });

  final int alarmId;
  final DateTime fireAt;
  final String label;
  final String soundAsset;
  final bool vibrate;

  /// Recurrence pattern for platforms that own recurrence (iOS). 0=Sun…6=Sat;
  /// empty = one-shot. Android ignores these and uses [fireAt].
  final int hour;
  final int minute;
  final Set<int> weekdays;
```

Update `==` to add `&& other.hour == hour && other.minute == minute && const SetEquality<int>().equals(other.weekdays, weekdays)` and `hashCode` to include `hour, minute, const SetEquality<int>().hash(weekdays)`. Add `import 'package:collection/collection.dart';` at the top (the package is already a dependency from Plan 1).

In `lib/domain/reconcile.dart`, `desiredOccurrences` builds each `ScheduledOccurrence` from an `Alarm`. Add the three fields to that construction:

```dart
      result.add(ScheduledOccurrence(
        alarmId: alarm.id,
        fireAt: next.toUtc(),
        label: alarm.label,
        soundAsset: alarm.soundAsset,
        vibrate: alarm.vibrate,
        hour: alarm.hour,
        minute: alarm.minute,
        weekdays: alarm.days,
      ));
```

In `lib/data/alarm_sync_service.dart`, `PigeonAlarmPlatform._toNative` builds the Pigeon `NativeAlarm`. Add the three fields (`weekdays` as a sorted list):

```dart
  NativeAlarm _toNative(ScheduledOccurrence o) => NativeAlarm(
        id: o.alarmId,
        fireAtEpochMs: o.fireAt.millisecondsSinceEpoch,
        label: o.label,
        soundAsset: o.soundAsset,
        vibrate: o.vibrate,
        hour: o.hour,
        minute: o.minute,
        weekdays: o.weekdays.toList()..sort(),
      );
```

> This uses the unprefixed `NativeAlarm` because the Pigeon import is still unaliased at Task 4. Task 5 adds `as pigeon` and rewrites this reference to `pigeon.NativeAlarm` — do not pre-empt that here.

- [ ] **Step 5: Implement the two new methods on Android (no-op path)**

The Kotlin `AlarmHostApiImpl` now fails to compile — the generated `AlarmHostApi` interface has two unimplemented members. Add them. In `android/app/src/main/kotlin/com/riseapp/rise/AlarmHostApiImpl.kt`, add inside the class (after `reconcileFinished`):

```kotlin
    override fun capabilities(): PlatformCapabilities =
        // Android always has real system alarms via AlarmManager.
        PlatformCapabilities(supportsSystemAlarms = true)

    override fun reconcileNotifications(requests: List<NotificationRequest>) {
        // No-op: Android schedules system alarms, never notification bursts.
        // The sync service only calls this when supportsSystemAlarms is false.
    }
```

> Android's `AlarmScheduler` reads only `fireAtEpochMs`/`id`/etc., never the new `hour`/`minute`/`weekdays`, so it needs no change — the generated `NativeAlarm` simply carries three fields Android ignores.

- [ ] **Step 6: Verify Dart analysis, tests, and the Android build**

```bash
flutter test
flutter analyze
flutter build apk --debug 2>&1 | tail -3
```
Expected: all tests green (Plan 1's suite still passes because the new `ScheduledOccurrence` fields default), `No issues found!`, and `✓ Built build/app/outputs/flutter-apk/app-debug.apk`.

> The iOS `AlarmApi.g.swift` also gained the new members, so the existing iOS build would break until the Swift impl (Tasks 6–10) adds them. That is expected — iOS is not built until Task 12.

- [ ] **Step 7: Commit**

```bash
git add pigeons/alarm_api.dart lib/data/native/alarm_api.g.dart android/app/src/main/kotlin/com/riseapp/rise/AlarmApi.g.kt ios/Runner/AlarmApi.g.swift android/app/src/main/kotlin/com/riseapp/rise/AlarmHostApiImpl.kt lib/domain/scheduled_occurrence.dart lib/domain/reconcile.dart lib/data/alarm_sync_service.dart
git commit -m "feat: carry recurrence + capabilities + notifications in the alarm contract"
```

---

### Task 5: Branch the sync service on platform capability

**Files:**
- Modify: `lib/data/alarm_sync_service.dart`
- Modify: `test/data/alarm_sync_service_test.dart`

**Interfaces:**
- Consumes: `allocateNotifications` / `droppedAlarmCount` (Task 3), domain `NotificationRequest` (Task 2), the Pigeon `capabilities`/`reconcileNotifications` (Task 4).
- Produces:
  - `AlarmPlatform` gains `Future<bool> supportsSystemAlarms()` and `Future<void> reconcileNotifications(List<NotificationRequest> requests)` (domain `NotificationRequest`).
  - `AlarmSyncService.reconcileNow` branches: system alarms → `reconcile(occurrences)` (unchanged); otherwise → `allocateNotifications` → `reconcileNotifications`, logging `droppedAlarmCount`.

- [ ] **Step 1: Write the failing test**

The existing test file defines `FakeAlarmPlatform implements AlarmPlatform`. Replace that fake and add two tests. Add these imports at the top of `test/data/alarm_sync_service_test.dart`:

```dart
import 'package:rise/domain/notification_request.dart';
```

Replace the `FakeAlarmPlatform` class with:

```dart
class FakeAlarmPlatform implements AlarmPlatform {
  FakeAlarmPlatform({this.systemAlarms = true});

  bool systemAlarms;
  final List<List<ScheduledOccurrence>> reconcileCalls = [];
  final List<ScheduledOccurrence> ringNowCalls = [];
  final List<List<NotificationRequest>> notificationCalls = [];

  @override
  Future<void> reconcile(List<ScheduledOccurrence> occurrences) async =>
      reconcileCalls.add(occurrences);

  @override
  Future<void> ringNow(ScheduledOccurrence occurrence) async =>
      ringNowCalls.add(occurrence);

  @override
  Future<bool> supportsSystemAlarms() async => systemAlarms;

  @override
  Future<void> reconcileNotifications(List<NotificationRequest> requests) async =>
      notificationCalls.add(requests);
}
```

Add these tests inside `main()`:

```dart
  test('system-alarm platform uses reconcile, not notifications', () async {
    platform = FakeAlarmPlatform(systemAlarms: true);
    AlarmSyncService.configure(AlarmSyncService(
      repository: repo,
      platform: platform,
      location: tz.getLocation('America/New_York'),
    ));
    await repo.upsert(const Alarm(id: 0, hour: 6, minute: 30));
    await AlarmSyncService.instance.reconcileNow();

    expect(platform.reconcileCalls, hasLength(1));
    expect(platform.notificationCalls, isEmpty);
  });

  test('fallback platform uses a notification burst, not reconcile', () async {
    platform = FakeAlarmPlatform(systemAlarms: false);
    AlarmSyncService.configure(AlarmSyncService(
      repository: repo,
      platform: platform,
      location: tz.getLocation('America/New_York'),
    ));
    await repo.upsert(const Alarm(id: 0, hour: 6, minute: 30));
    await AlarmSyncService.instance.reconcileNow();

    expect(platform.notificationCalls, hasLength(1));
    // A single alarm gets a full 16-notification burst.
    expect(platform.notificationCalls.single, hasLength(16));
    expect(platform.reconcileCalls, isEmpty,
        reason: 'the fallback platform must not arm system alarms');
  });
```

> The existing `FakeAlarmPlatform` in this file may already have `reconcile`/`ringNow` only; replacing the whole class (as above) keeps the file's other tests working because those two members are preserved.

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/data/alarm_sync_service_test.dart
```
Expected: FAIL — `AlarmPlatform` has no `supportsSystemAlarms`/`reconcileNotifications`, and `AlarmSyncService` never calls them.

- [ ] **Step 3: Extend `AlarmPlatform` and `PigeonAlarmPlatform`**

In `lib/data/alarm_sync_service.dart`:

The file currently imports `import 'native/alarm_api.g.dart';`. The Pigeon-generated `NotificationRequest` would collide with the domain one, so alias the Pigeon import. Change that line to:

```dart
import 'native/alarm_api.g.dart' as pigeon;
```

and update the three existing references in `PigeonAlarmPlatform` to use the prefix: `pigeon.AlarmHostApi` (the field type and the two constructor uses) and `pigeon.NativeAlarm` (in `_toNative`). Add the domain import near the other domain imports:

```dart
import '../domain/notification_budget.dart';
import '../domain/notification_request.dart';
```

Add the two methods to `abstract class AlarmPlatform`:

```dart
  /// Whether this platform can schedule true system alarms. When false the
  /// sync service sends a notification burst instead of [reconcile].
  Future<bool> supportsSystemAlarms();

  /// Replaces the platform's scheduled notification set (iOS 16–25 fallback).
  Future<void> reconcileNotifications(List<NotificationRequest> requests);
```

Implement them in `PigeonAlarmPlatform`:

```dart
  @override
  Future<bool> supportsSystemAlarms() async =>
      (await _api.capabilities()).supportsSystemAlarms;

  @override
  Future<void> reconcileNotifications(List<NotificationRequest> requests) =>
      _api.reconcileNotifications([
        for (final r in requests)
          pigeon.NotificationRequest(
            alarmId: r.alarmId,
            fireAtEpochMs: r.fireAtEpochMs,
            label: r.label,
            sound: r.sound,
            burstIndex: r.burstIndex,
            burstTotal: r.burstTotal,
          )
      ]);
```

- [ ] **Step 4: Branch `reconcileNow`**

In `AlarmSyncService.reconcileNow`, the current body computes `plan` (a `List<ScheduledOccurrence>`) and calls `await _platform.reconcile(plan)`. Replace that single call with a capability branch (keep the recovery block that follows unchanged):

```dart
    final plan = await currentPlan();

    if (await _platform.supportsSystemAlarms()) {
      await _platform.reconcile(plan);
    } else {
      final now = tz.TZDateTime.now(_location);
      final requests =
          allocateNotifications(occurrences: plan, now: now.toUtc());
      final dropped =
          droppedAlarmCount(occurrences: plan, now: now.toUtc());
      if (dropped > 0) {
        debugPrint('Rise: $dropped alarm(s) exceed the iOS notification cap '
            'and will not fire until sooner alarms pass');
      }
      await _platform.reconcileNotifications(requests);
    }

    if (!recoverMissed) return;
```

> `allocateNotifications` expects a UTC `now`; `tz.TZDateTime.now(_location).toUtc()` gives it. The recovery block below this (the `previousOccurrence`/`ringNow` logic) is unchanged — missed-alarm recovery still uses `ringNow` on both platforms.

- [ ] **Step 5: Run the test to verify it passes**

```bash
flutter test test/data/alarm_sync_service_test.dart
```
Expected: PASS — the two new tests plus the existing ones.

- [ ] **Step 6: Run the whole suite and analyze**

```bash
flutter test
flutter analyze
```
Expected: all green; `No issues found!`.

- [ ] **Step 7: Commit**

```bash
git add lib/data/alarm_sync_service.dart test/data/alarm_sync_service_test.dart
git commit -m "feat: branch reconcile between system alarms and notification burst"
```

---

## Task group C — the Swift engine (verified via Codemagic build, not locally)

**Read this before any Swift task.** None of these files can be compiled or run on the Windows dev machine. Each task's code is the researched best-effort implementation (API from `docs/superpowers/research/2026-07-16-alarmkit-ios26-api.md`). A few API points could not be pinned from docs alone and are flagged **⚠️ VERIFY AT BUILD** inline — for those, **the Codemagic compiler (Task 12) is the source of truth; fix the code against its errors, not against this plan.** Do not mark a Swift task "done" on the strength of reading it — it is done when Task 12's build is green and, for behavior, when Task 14's device run passes. Write each file, commit, and move on; the whole group is validated together at Task 12.

### Task 6: The Swift AlarmEngine protocol

**Files:**
- Create: `ios/Runner/Alarm/AlarmEngine.swift`

**Interfaces:**
- Consumes: the Pigeon-generated `NativeAlarm`, `NotificationRequest` structs (from `AlarmApi.g.swift`, Task 4).
- Produces: `protocol AlarmEngine` with `reconcile`, `reconcileNotifications`, `ringNow`, `cancelAll`, `ringingAlarmId`, `stopRinging`, `supportsSystemAlarms` — the seam `AlarmHostApiImpl` (Task 10) dispatches to, implemented by `NotificationEngine` (Task 7) and `AlarmKitEngine` (Task 8).

- [ ] **Step 1: Write the protocol**

Create `ios/Runner/Alarm/AlarmEngine.swift`:

```swift
import Foundation

/// What Rise's iOS alarm engines can do. AlarmHostApiImpl selects a concrete
/// engine at runtime by OS version and dispatches the Pigeon calls to it.
///
/// The Pigeon protocol methods are synchronous `throws`, but AlarmKit is async.
/// Engines therefore do their async work in a detached `Task {}` and return
/// immediately — reconcile is fire-and-forget; nothing on the Dart side awaits
/// the platform result. `ringingAlarmId()` reads synchronous state only.
protocol AlarmEngine {
    /// True when this engine schedules real system alarms (AlarmKit). False for
    /// the notification fallback.
    var supportsSystemAlarms: Bool { get }

    /// Full replace of the scheduled system-alarm set. Used only when
    /// `supportsSystemAlarms` is true.
    func reconcile(_ alarms: [NativeAlarm])

    /// Full replace of the scheduled notification set (the iOS 16–25 fallback).
    /// Used only when `supportsSystemAlarms` is false.
    func reconcileNotifications(_ requests: [NotificationRequest])

    /// Ring one alarm now without touching the scheduled set (missed-alarm
    /// recovery). Never routes through `reconcile`.
    func ringNow(_ alarm: NativeAlarm)

    func cancelAll()

    /// The id of the alarm currently alerting, or nil. Peek only — does not
    /// clear state. The notification fallback returns nil (it has no queryable
    /// "ringing" state; the notification simply fired).
    func ringingAlarmId() -> Int64?

    /// Stop the alarm with this id if it is the one alerting.
    func stopRinging(_ alarmId: Int64)
}
```

- [ ] **Step 2: Commit**

```bash
git add ios/Runner/Alarm/AlarmEngine.swift
git commit -m "feat(ios): add the AlarmEngine protocol seam"
```

---

### Task 7: NotificationEngine — the iOS 16–25 fallback

**Files:**
- Create: `ios/Runner/Alarm/NotificationEngine.swift`

**Interfaces:**
- Consumes: `AlarmEngine` (Task 6), `NotificationRequest`/`NativeAlarm` (Pigeon).
- Produces: `final class NotificationEngine: AlarmEngine` with `supportsSystemAlarms == false`.

Honest scope: on iOS 16–25 there is no system-alarm API. The engine schedules the Dart-allocated burst as Time-Sensitive local notifications (≤30 s sound each, 30 s apart) — an approximation of a ringing alarm, not a true one. There is no persistent "ringing" state to query, so `ringingAlarmId()` returns nil and the app relies on the user tapping the notification. This is the "honest degradation" the spec accepts for pre-26.

- [ ] **Step 1: Write the engine**

Create `ios/Runner/Alarm/NotificationEngine.swift`:

```swift
import Foundation
import UserNotifications

/// iOS 16–25 fallback: approximates a ringing alarm with a burst of
/// Time-Sensitive local notifications. The Dart budget allocator already chose
/// how many and when (≤64 total); this only schedules them.
final class NotificationEngine: AlarmEngine {
    var supportsSystemAlarms: Bool { false }

    private let center = UNUserNotificationCenter.current()
    private let prefix = "rise-alarm-"

    func reconcile(_ alarms: [NativeAlarm]) {
        // Not used on this engine (supportsSystemAlarms is false), but the
        // protocol requires it. No-op.
    }

    func reconcileNotifications(_ requests: [NotificationRequest]) {
        // Full replace: drop everything we scheduled, then add the new burst.
        removeAllRiseNotifications { [weak self] in
            guard let self = self else { return }
            let nowMs = Date().timeIntervalSince1970 * 1000.0
            for r in requests {
                let seconds = max(1.0, (Double(r.fireAtEpochMs) - nowMs) / 1000.0)
                self.center.add(self.makeRequest(
                    alarmId: r.alarmId, burstIndex: r.burstIndex,
                    label: r.label, sound: r.sound, after: seconds))
            }
        }
    }

    func ringNow(_ alarm: NativeAlarm) {
        // Fire a single notification ~1 s out (missed-alarm recovery).
        center.add(makeRequest(
            alarmId: alarm.id, burstIndex: 0,
            label: alarm.label, sound: alarm.soundAsset, after: 1.0))
    }

    func cancelAll() { removeAllRiseNotifications(then: nil) }

    func ringingAlarmId() -> Int64? {
        // No queryable ringing state on the fallback.
        return nil
    }

    func stopRinging(_ alarmId: Int64) {
        // Cancel any not-yet-fired burst notifications for this alarm.
        center.getPendingNotificationRequests { requests in
            let ids = requests.map { $0.identifier }
                .filter { $0.hasPrefix("\(self.prefix)\(alarmId)-") }
            self.center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    private func makeRequest(alarmId: Int64, burstIndex: Int64, label: String,
                             sound: String, after seconds: Double) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = label.isEmpty ? "Alarm" : label
        content.body = burstIndex == 0 ? "Time to wake up" : "Still ringing…"
        content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: sound))
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive  // breaks Focus, not the mute switch
        }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let id = "\(prefix)\(alarmId)-\(burstIndex)"
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }

    private func removeAllRiseNotifications(then completion: (() -> Void)?) {
        center.getPendingNotificationRequests { [weak self] requests in
            guard let self = self else { completion?(); return }
            let ids = requests.map { $0.identifier }.filter { $0.hasPrefix(self.prefix) }
            self.center.removePendingNotificationRequests(withIdentifiers: ids)
            completion?()
        }
    }
}
```

> `UNNotificationSound(named:)` expects the bundled `default_alarm.wav` (Task 1). The allocator passes each alarm's `soundAsset`; Plan 1's default is `default_alarm.wav`. A missing sound file falls back to the default system sound — acceptable.

- [ ] **Step 2: Commit**

```bash
git add ios/Runner/Alarm/NotificationEngine.swift
git commit -m "feat(ios): add the iOS 16-25 notification fallback engine"
```

---

### Task 8: AlarmKitEngine — the iOS 26+ system alarm

**Files:**
- Create: `ios/Runner/Alarm/AlarmKitEngine.swift`

**Interfaces:**
- Consumes: `AlarmEngine` (Task 6), `NativeAlarm` (Pigeon), AlarmKit.
- Produces: `@available(iOS 26.0, *) final class AlarmKitEngine: AlarmEngine` with `supportsSystemAlarms == true`.

- [ ] **Step 1: Write the engine**

Create `ios/Runner/Alarm/AlarmKitEngine.swift`:

```swift
import Foundation
import SwiftUI
import AlarmKit

/// Empty metadata — Rise attaches no custom data to its alarms yet. AlarmMetadata
/// is a marker protocol (Codable, Hashable, Sendable).
@available(iOS 26.0, *)
struct RiseAlarmMetadata: AlarmMetadata {}

/// iOS 26+ system-alarm engine. Uses AlarmKit's native recurrence so repeating
/// alarms re-arm without any background trigger (iOS has none). Requires the
/// NSAlarmKitUsageDescription Info.plist string — and NO entitlement.
@available(iOS 26.0, *)
final class AlarmKitEngine: AlarmEngine {
    var supportsSystemAlarms: Bool { true }

    private let manager = AlarmManager.shared

    // Map our Int64 alarm id ↔ a deterministic UUID so reconcile can cancel and
    // replace exactly the alarms we own.
    private func uuid(for id: Int64) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012llx", id))!
    }
    private func id(from uuid: UUID) -> Int64? {
        let hex = uuid.uuidString.replacingOccurrences(of: "-", with: "").suffix(12)
        return Int64(hex, radix: 16)
    }

    func reconcile(_ alarms: [NativeAlarm]) {
        Task { await self.replaceAll(with: alarms) }
    }

    func ringNow(_ alarm: NativeAlarm) {
        // Immediate one-shot ~2 s out, without cancelling the scheduled set.
        var immediate = alarm
        immediate.weekdays = []  // force a fixed one-shot
        immediate.fireAtEpochMs = Int64(Date().timeIntervalSince1970 * 1000) + 2000
        Task { try? await self.schedule(immediate, idOffset: 0x1000_0000_0000) }
    }

    func reconcileNotifications(_ requests: [NotificationRequest]) {
        // Not used on this engine.
    }

    func cancelAll() {
        Task {
            for alarm in manager.alarms { try? await manager.cancel(id: alarm.id) }
        }
    }

    func ringingAlarmId() -> Int64? {
        // ⚠️ VERIFY AT BUILD: the exact way to detect an "alerting" alarm. The
        // research confirmed `AlarmManager.shared.alarms: [Alarm]` and that Alarm
        // carries state, but the exact state enum/case name for "alerting" could
        // not be pinned from docs. If `alarm.state == .alerting` does not
        // compile, check the Alarm.State cases surfaced by the compiler and use
        // the alerting case. As a fallback that always compiles, returning the
        // first alarm's id is wrong; prefer fixing against the real state.
        for alarm in manager.alarms {
            if isAlerting(alarm) { return id(from: alarm.id) }
        }
        return nil
    }

    func stopRinging(_ alarmId: Int64) {
        let target = uuid(for: alarmId)
        Task {
            if manager.alarms.contains(where: { $0.id == target }) {
                try? await manager.stop(id: target)
            }
        }
    }

    // MARK: - private

    private func replaceAll(with alarms: [NativeAlarm]) async {
        for existing in manager.alarms { try? await manager.cancel(id: existing.id) }
        for a in alarms { try? await schedule(a, idOffset: 0) }
    }

    private func schedule(_ a: NativeAlarm, idOffset: Int64) async throws {
        let alarmId = uuid(for: a.id &+ idOffset)

        let schedule: Alarm.Schedule
        if a.weekdays.isEmpty {
            let date = Date(timeIntervalSince1970: Double(a.fireAtEpochMs) / 1000.0)
            schedule = .fixed(date)
        } else {
            let time = Alarm.Schedule.Relative.Time(hour: Int(a.hour), minute: Int(a.minute))
            let days = a.weekdays.map { weekday(fromIndex: Int($0)) }
            schedule = .relative(.init(time: time, repeats: .weekly(days)))
        }

        // ⚠️ VERIFY AT BUILD: the non-deprecated AlarmPresentation.Alert init is
        // `init(title:secondaryButton:secondaryButtonBehavior:)` (the system
        // provides Stop). If the compiler wants the `stopButton:` form, that is
        // the deprecated one — prefer the two-argument form. Plan 4 adds a
        // secondary "mission" button + intent; Plan 2 ships Stop-only.
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: a.label.isEmpty ? "Alarm" : a.label),
            secondaryButton: nil,
            secondaryButtonBehavior: nil
        )
        let attributes = AlarmAttributes(
            presentation: AlarmPresentation(alert: alert),
            metadata: RiseAlarmMetadata(),
            tintColor: Color.orange
        )
        let config = AlarmManager.AlarmConfiguration(
            countdownDuration: nil,
            schedule: schedule,
            attributes: attributes,
            stopIntent: nil,
            secondaryIntent: nil,
            sound: .named(a.soundAsset)
        )
        _ = try await manager.schedule(id: alarmId, configuration: config)
    }

    private func weekday(fromIndex i: Int) -> Locale.Weekday {
        switch i {  // domain: 0=Sun … 6=Sat
        case 0: return .sunday
        case 1: return .monday
        case 2: return .tuesday
        case 3: return .wednesday
        case 4: return .thursday
        case 5: return .friday
        default: return .saturday
        }
    }

    private func isAlerting(_ alarm: Alarm) -> Bool {
        // ⚠️ VERIFY AT BUILD (see ringingAlarmId). Best-effort against the
        // documented state model.
        return "\(alarm.state)".lowercased().contains("alert")
    }
}
```

> `ringNow`/`schedule` use an `idOffset` so an immediate recovery ring gets a UUID distinct from the alarm's scheduled UUID (mirrors Android's dedicated request code). `0x1000_0000_0000` stays clear of real ids (which are small autoincrement values). `&+` is Swift's overflow-safe add.
>
> `authorization` is requested lazily by AlarmKit on first `schedule`; the Setup Guardian's explicit request lives in Task 10's `requestNotificationPermission`/`getPermissions`.

- [ ] **Step 2: Commit**

```bash
git add ios/Runner/Alarm/AlarmKitEngine.swift
git commit -m "feat(ios): add the iOS 26+ AlarmKit engine with native recurrence"
```

---

### Task 9: AlarmHostApiImpl — Pigeon impl + engine selection + permissions

**Files:**
- Create: `ios/Runner/Alarm/AlarmHostApiImpl.swift`

**Interfaces:**
- Consumes: `AlarmEngine`, `AlarmKitEngine`, `NotificationEngine`, and the Pigeon `AlarmHostApi` protocol, `AlarmPermissions`, `PlatformCapabilities`, `NativeAlarm`, `NotificationRequest` (all from `AlarmApi.g.swift`).
- Produces: `final class AlarmHostApiImpl: AlarmHostApi` — registered by `AppDelegate` (Task 10).

- [ ] **Step 1: Write the impl**

Create `ios/Runner/Alarm/AlarmHostApiImpl.swift`:

```swift
import Foundation
import UserNotifications
import UIKit

/// Implements the Pigeon AlarmHostApi on iOS. Selects the engine once by OS
/// version: AlarmKit on 26+, local notifications on 16–25.
final class AlarmHostApiImpl: AlarmHostApi {
    private let engine: AlarmEngine

    init() {
        if #available(iOS 26.0, *) {
            engine = AlarmKitEngine()
        } else {
            engine = NotificationEngine()
        }
    }

    func reconcile(alarms: [NativeAlarm]) throws { engine.reconcile(alarms) }
    func reconcileNotifications(requests: [NotificationRequest]) throws {
        engine.reconcileNotifications(requests)
    }
    func ringNow(alarm: NativeAlarm) throws { engine.ringNow(alarm) }
    func cancelAll() throws { engine.cancelAll() }
    func getRingingAlarmId() throws -> Int64? { engine.ringingAlarmId() }
    func stopRinging(alarmId: Int64) throws { engine.stopRinging(alarmId) }

    /// No headless-engine lifecycle on iOS (no boot receiver). No-op.
    func reconcileFinished() throws {}

    func capabilities() throws -> PlatformCapabilities {
        PlatformCapabilities(supportsSystemAlarms: engine.supportsSystemAlarms)
    }

    func getPermissions() throws -> AlarmPermissions {
        // Notifications: queried synchronously from a cached snapshot the app
        // refreshes on launch/resume (Task 10 wires the refresh). Here we read
        // the current authorization synchronously via a semaphore-bounded call.
        let notificationsGranted = Self.notificationsAuthorizedSync()

        // On iOS there is no "exact alarm", "full-screen intent", or "battery
        // unrestricted" concept. Map exactAlarm to "system alarms available"
        // (true on 26+, where AlarmKit is the exact-alarm equivalent); report
        // the two Android-only gates as satisfied so the Setup Guardian shows
        // them green rather than false-red on iOS.
        let systemAlarms = engine.supportsSystemAlarms
        return AlarmPermissions(
            notifications: notificationsGranted,
            exactAlarm: systemAlarms,
            fullScreenIntent: true,
            batteryUnrestricted: true
        )
    }

    func requestNotificationPermission() throws {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]) { _, _ in }
        // AlarmKit authorization is requested lazily on first schedule; on 26+
        // we could also prompt here, but the first alarm the user sets prompts.
    }

    // The Android settings-deep-link methods have no iOS equivalent; open the
    // app's Settings page so the Setup Guardian's "Fix" still does something.
    func openExactAlarmSettings() throws { Self.openAppSettings() }
    func openBatterySettings() throws { Self.openAppSettings() }
    func openFullScreenIntentSettings() throws { Self.openAppSettings() }

    // MARK: - helpers

    private static func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            DispatchQueue.main.async { UIApplication.shared.open(url) }
        }
    }

    private static func notificationsAuthorizedSync() -> Bool {
        let sem = DispatchSemaphore(value: 0)
        var granted = false
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            granted = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 1.0)
        return granted
    }
}
```

> `getPermissions` runs on a background Pigeon thread, so the 1 s semaphore wait for notification settings is safe (never on the main thread). If a future refactor calls it on the main thread, replace the semaphore with a cached value refreshed asynchronously.

- [ ] **Step 2: Commit**

```bash
git add ios/Runner/Alarm/AlarmHostApiImpl.swift
git commit -m "feat(ios): implement the Pigeon AlarmHostApi with engine selection"
```

---

### Task 10: Register the impl and the notification delegate

**Files:**
- Modify: `ios/Runner/AppDelegate.swift`

**Interfaces:**
- Consumes: `AlarmHostApiImpl` (Task 9), `AlarmHostApiSetup` (Pigeon).
- Produces: an app that wires the host API to the Flutter engine and shows notifications while foregrounded.

- [ ] **Step 1: Wire it up**

Replace `ios/Runner/AppDelegate.swift` with:

```swift
import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var alarmApi: AlarmHostApiImpl?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let impl = AlarmHostApiImpl()
      AlarmHostApiSetup.setUp(
        binaryMessenger: controller.binaryMessenger, api: impl)
      self.alarmApi = impl
    }

    // Show the notification banner + play its sound even while the app is
    // foregrounded, so the fallback burst is audible when Rise is open.
    UNUserNotificationCenter.current().delegate = self

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler:
      @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound, .list])
  }
}
```

> `AlarmHostApiSetup.setUp` is the Pigeon-generated registrar (seen in `AlarmApi.g.swift`). `FlutterAppDelegate` already conforms to `UNUserNotificationCenterDelegate`; overriding `willPresent` opts the fallback notifications into foreground audio.

- [ ] **Step 2: Commit**

```bash
git add ios/Runner/AppDelegate.swift
git commit -m "feat(ios): register the alarm host API and notification delegate"
```

---

## Task group D — build, ship, and verify on hardware (deferred; needs the Apple Developer account)

Everything below is **gated on an Apple Developer Program membership ($99/yr) and a physical iPhone running iOS 26**, which the user supplies. This is the "test steps at the end" phase. The Apple-side prerequisites checklist and the full `codemagic.yaml` are in `docs/superpowers/research/2026-07-16-codemagic-ios-from-windows.md`.

### Task 11: Add the Codemagic pipeline

**Files:**
- Create: `codemagic.yaml`

**Interfaces:**
- Consumes: the whole Flutter project.
- Produces: a CI workflow that builds, signs, and ships the iOS app to TestFlight.

- [ ] **Step 1: Write `codemagic.yaml`**

Create `codemagic.yaml` at the repo root (adapt `APP_STORE_APPLE_ID` after the app record exists — Task 13):

```yaml
workflows:
  ios-workflow:
    name: Rise iOS
    max_build_duration: 120
    instance_type: mac_mini_m2
    integrations:
      app_store_connect: codemagic      # name of the API key in Codemagic Team settings
    environment:
      ios_signing:
        distribution_type: app_store
        bundle_identifier: com.riseapp.rise
      vars:
        APP_STORE_APPLE_ID: 0000000000   # numeric Apple ID of the App Store Connect record
      flutter: stable
      xcode: "26.4"                       # iOS 26 SDK for AlarmKit
      cocoapods: default
    scripts:
      - name: Set up code signing
        script: xcode-project use-profiles
      - name: Get Flutter packages
        script: flutter pub get
      - name: Install pods
        script: find . -name "Podfile" -execdir pod install \;
      - name: Flutter analyze
        script: flutter analyze
      - name: Flutter unit tests
        script: flutter test
      - name: Flutter build ipa
        script: |
          flutter build ipa --release \
            --build-name=1.0.0 \
            --build-number=$(($(app-store-connect get-latest-app-store-build-number "$APP_STORE_APPLE_ID") + 1)) \
            --export-options-plist=/Users/builder/export_options.plist
    artifacts:
      - build/ios/ipa/*.ipa
      - /tmp/xcodebuild_logs/*.log
    publishing:
      app_store_connect:
        auth: integration
        submit_to_testflight: true
        beta_groups:
          - Internal Testers
        submit_to_app_store: false
```

- [ ] **Step 2: Commit**

```bash
git add codemagic.yaml
git commit -m "ci: add Codemagic iOS build + TestFlight workflow"
```

---

### Task 12: First Codemagic build — make the Swift compile

**Files:** none (CI run + fixes against compiler errors).

**Prerequisite (user):** Apple Developer Program membership; App Store Connect API key uploaded to Codemagic and named `codemagic`; the repo connected to Codemagic. (Full checklist in the Codemagic research doc.)

This is where all of Task group C is actually validated. The Swift was written without a compiler; the first build will surface real API mismatches — especially the **⚠️ VERIFY AT BUILD** points in `AlarmKitEngine` (the `Alarm` alerting-state check, the exact `AlarmPresentation.Alert` init, custom-sound naming).

- [ ] **Step 1: Trigger the build (compile-only first pass)**

The goal here is only to make the Swift compile — the App Store Connect app record (and its `APP_STORE_APPLE_ID`) does not exist yet (Task 13 creates it). So for this first pass, temporarily simplify the build so it does not depend on the app id or publishing:
- change the `Flutter build ipa` script's build-number to a literal `--build-number=1` (the `app-store-connect get-latest-app-store-build-number "$APP_STORE_APPLE_ID"` call needs a real app id);
- set `publishing.app_store_connect.submit_to_testflight: false` for now.

Commit that as a temporary change, push the branch, and start the `ios-workflow` build. Watch the `Flutter build ipa` step. Task 13 restores the auto-increment build number and TestFlight upload once the app record exists.

- [ ] **Step 2: Fix compile errors against the compiler, not the plan**

For each Swift error, fix the code to match what Xcode 26's AlarmKit SDK actually declares. Likely fixes, in order of probability:
- `AlarmKitEngine.isAlerting` / `ringingAlarmId`: replace the stringly `alarm.state` check with the real `Alarm.State` enum case the compiler names.
- `AlarmPresentation.Alert(...)`: if the two-arg init is rejected, read the compiler's suggested signature and use the non-deprecated one.
- `AlarmManager.AlarmConfiguration(...)`: if the memberwise init differs, use the `.alarm(schedule:attributes:stopIntent:secondaryIntent:sound:)` factory instead.
- `sound: .named(...)`: if `AlertConfiguration.AlertSound` is namespaced differently, follow the compiler.
- If the build fails with **"Provisioning profile doesn't include the com.apple.developer.alarmkit entitlement"** — **do not add that entitlement (it does not exist).** Remove any `*.entitlements` AlarmKit key; the fix is deletion. (This is the documented LLM trap — see the research doc.)

Re-run until the build is green. Commit each fix with a message naming the SDK reality it corrected.

- [ ] **Step 3: Confirm green**

Expected: Codemagic reports the `ios-workflow` build succeeded and an `.ipa` artifact is produced. Only now is Task group C "compiles".

- [ ] **Step 4: Record what the SDK actually required**

Append the real signatures the compiler forced (the alerting-state check especially) to `docs/superpowers/research/2026-07-16-alarmkit-ios26-api.md` under a "Confirmed at build" heading, so Plan 4's mission/secondary-button work starts from fact.

```bash
git add docs/superpowers/research/2026-07-16-alarmkit-ios26-api.md
git commit -m "docs: record AlarmKit signatures confirmed by the Codemagic build"
```

---

### Task 13: TestFlight to a physical iPhone

**Files:** none (App Store Connect setup + install).

**Prerequisite (user):** the app record created in App Store Connect (its numeric Apple ID goes into `codemagic.yaml`'s `APP_STORE_APPLE_ID`); an Internal Testing group named "Internal Testers" with the user added; TestFlight installed on an iOS 26 iPhone.

- [ ] **Step 1: Set `APP_STORE_APPLE_ID` and rebuild**

Put the app record's numeric Apple ID into `codemagic.yaml`, commit, and run the workflow so `submit_to_testflight: true` uploads the build.

```bash
git add codemagic.yaml
git commit -m "ci: set App Store Connect app id for TestFlight upload"
```

- [ ] **Step 2: Install on the iPhone**

After the build's post-processing finishes (~5–30 min), the build appears in TestFlight on the iPhone. Install it. Expected: Rise launches, and the throwaway `DevHomePage` shows the Setup Guardian with Notifications and (on iOS 26) system-alarm capability.

---

### Task 14: iOS reliability protocol on the iPhone

**Files:**
- Create: `docs/superpowers/reliability/<date>-plan2-ios-results.md`

**Interfaces:**
- Consumes: the TestFlight build on hardware.
- Produces: a signed-off iOS results table. **This is the Plan 2 launch gate** (spec §9), mirroring Android's.

**Prerequisite (user):** the iOS 26 iPhone with the TestFlight build.

- [ ] **Step 1: Run the matrix**

For each scenario, set a ~2-minute alarm from `DevHomePage`, apply the condition, and record whether it rang, how late, and how it presented.

| # | Scenario | How to apply | Pass criterion |
|---|----------|--------------|----------------|
| 1 | Screen locked | Lock, wait | AlarmKit alert rings over the Lock Screen |
| 2 | App backgrounded | Home, wait | Rings |
| 3 | App force-quit (swiped from switcher) | Swipe away, wait | Rings (AlarmKit is system-held) |
| 4 | **Silent switch on** | Flip the mute switch | **Rings** (AlarmKit breaks silent) |
| 5 | Focus / Do Not Disturb on | Enable a Focus | Rings (AlarmKit breaks Focus) |
| 6 | Volume at 0 | Volume down fully | Rings (alarm volume, not media) |
| 7 | After reboot | Restart the iPhone, wait for the alarm | Rings (system daemon holds it) |
| 8 | Repeating alarm next day | Set a daily alarm, wait to the next day | Rings again (native recurrence, no app open) |
| 9 | Stop button | Tap Stop on the alert | Alarm silences |
| 10 | Airplane mode | Toggle on | Rings (no network dependency) |
| 11 | Custom sound | Set an alarm, confirm the bundled sound plays | Bundled sound plays (not silence) |
| 12 | Low battery | Drain < 20% | Rings |

> On an iOS 16–25 device (if one is available), separately confirm the fallback: a set alarm produces the Time-Sensitive notification burst, audible with the app foregrounded; note honestly that force-quit + silent on pre-26 degrades to vibrate-only (spec-accepted).

- [ ] **Step 2: Record results and verdict**

Fill the table in `docs/superpowers/reliability/<date>-plan2-ios-results.md` (mirror the Android results doc). **Gate: every should-ring scenario rings on iOS 26.** Scenario 11 (custom sound) is the one the research specifically flagged as flaky — if it fails, that is a real finding to fix (try `.caf` via `afconvert`, or fall back to `.default`), not a pass to fudge.

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/reliability/
git commit -m "test: record iOS reliability protocol results"
```

---

## Definition of done

- [ ] Pure-Dart tasks (allocator, contract, branching) pass `flutter test` on Windows, and the Android build still succeeds (regression check — the contract change must not break Plan 1).
- [ ] The Codemagic `ios-workflow` build is green (Task group C compiles against the real iOS 26 SDK).
- [ ] The build is on the user's iPhone via TestFlight.
- [ ] The iOS reliability matrix passes on iOS 26: rings through the silent switch, Focus, force-quit, and reboot; a repeating alarm re-arms across days with no app launch.
- [ ] No `com.apple.developer.alarmkit` entitlement anywhere.

## What Plan 3 picks up

The real design-system UI (replacing `DevHomePage`/`DevRingPage`), the shared ring/dismiss experience, and — for iOS — wiring the AlarmKit `secondaryIntent` to open the app for a dismiss mission (Plan 4 owns missions, but the App Intent plumbing is designed here). Recording an iOS dismissal back to the Drift DB (one-shot disable, recovery suppression) via the `stopIntent`/`alarmUpdates` signal is also Plan 4 work, flagged in the AlarmKit research doc.

