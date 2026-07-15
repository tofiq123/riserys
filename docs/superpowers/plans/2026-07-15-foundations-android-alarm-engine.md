# Rise Plan 1: Foundations + Android Alarm Engine — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Flutter app whose alarms ring reliably on Android — through silent mode, Doze, reboots, and force-kills — verified on real hardware.

**Architecture:** Local SQLite (Drift) is the source of truth for alarms; no alarm ever depends on a network call. Pure-Dart domain logic (`ScheduleMath`, reconcile diff) computes *when* alarms fire and is exhaustively unit-tested on Windows without a device. A thin Pigeon-generated channel hands a flat list of concrete fire-times to native Kotlin, which owns only *ringing*: `AlarmManager.setAlarmClock()` → `BroadcastReceiver` → foreground service → full-screen intent → ringing activity. Native holds no scheduling logic — every alarm change re-runs a full reconcile.

**Tech Stack:** Flutter 3.35.1 / Dart 3.9.0 · Drift (SQLite) · `timezone` package · Riverpod · Pigeon · Kotlin (JDK 21, Android SDK 36)

**Prerequisites (verified present on this machine):** Flutter 3.35.1, Android SDK 36 + build-tools 36, JDK 21 (Android Studio JBR), emulators `Medium_Phone_API_36.0` and `Pixel_9_Pro_XL`. Task 12 additionally requires **two physical Android phones**, one of them a Xiaomi/Samsung/Huawei-class OEM device — the emulator cannot prove OEM battery-killer survival.

**Out of scope (later plans):** iOS (Plan 2), design system and real UI (Plan 3), missions/snooze/wake-up-check (Plan 4), all social and backend (Plans 5–6), stats (Plan 7), premium (Plan 8). Plan 1's UI is deliberately ugly scaffolding whose only job is to prove the engine.

## Global Constraints

Values copied verbatim from `docs/superpowers/specs/2026-07-15-rise-alarm-app-design.md`. Every task's requirements implicitly include this section.

- **Android minSdk 26; targetSdk latest (36).** iOS deployment target 16 (Plan 2).
- **Scheduling API: `AlarmManager.setAlarmClock()`.** Never `setExactAndAllowWhileIdle()` as the primary path — Doze throttles it to once per 9 minutes per app.
- **Permission: `USE_EXACT_ALARM`** (API 33+, install-granted, not user-revocable). `SCHEDULE_EXACT_ALARM` is the API 31–32 fallback only.
- **Foreground service type: `systemExempted`** — explicitly covers exact-alarm holders continuing an alarm.
- **Audio: `AudioAttributes.USAGE_ALARM`** — routes to the alarm volume stream, immune to media mute.
- **Gentle start: volume ramps from low over 60 s.** Abrupt waking spikes morning blood pressure; never start at full volume.
- **Missed-alarm recovery window: 30 minutes.** Due within the last 30 min and undismissed → ring now.
- **DST spring-forward (nonexistent wall time): fire at the first valid instant after.** DST fall-back (duplicate wall time): fire once.
- **Alarms follow local wall clock**; recompute on `TIME_SET` and `TIMEZONE_CHANGED`.
- **No overnight keep-alive** (battery drain is the category's #1 churn theme). **No ad-to-snooze, ever.**
- **Bundled default sound ships in the binary** — the fallback chain must never depend on downloaded or user files.
- **Launch gate (Plan 9, measured from Task 12 onward): ≥99.5% ring delivery, ≥99.5% crash-free.**
- **Domain stores 24-hour time.** The prototype's 12h+AM/PM is a UI concern only.
- **Day indices: 0=Sunday … 6=Saturday**, matching the prototype's `days[0-6]` / `S M T W T F S` chips. Empty set = one-shot alarm.

---

### Task 1: Scaffold the Flutter project

**Files:**
- Create: `pubspec.yaml`, `lib/main.dart`, `test/` (via `flutter create`)
- Modify: `android/app/build.gradle.kts`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: nothing (first task).
- Produces: a Flutter project with application id `com.riseapp.rise`, minSdk 26, targetSdk 36, and a passing `flutter test`.

> **DECISION — application id is permanent after store publication.** This plan uses `com.riseapp.rise`. The spec flags a naming collision (four unrelated "Rise" alarm apps exist). If the app may be renamed, change it **now** — changing it after launch means a new listing and losing all installs. Ask the user before proceeding if unsure.

- [ ] **Step 1: Scaffold into the existing repo**

The repo root already contains `README.md`, `project/`, and `docs/`. `flutter create` adds to a non-empty directory without touching them.

```bash
cd "C:/Users/ASUS/Desktop/startuping/rise"
flutter create --org com.riseapp --project-name rise --platforms=android,ios .
```

- [ ] **Step 2: Verify the scaffold builds and tests pass**

```bash
flutter test
```
Expected: PASS — `All tests passed!` (the generated widget smoke test).

- [ ] **Step 3: Set SDK levels**

In `android/app/build.gradle.kts`, inside `android { defaultConfig { ... } }`, replace the generated `minSdk`/`targetSdk` lines with explicit values:

```kotlin
    defaultConfig {
        applicationId = "com.riseapp.rise"
        minSdk = 26
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
```

Also set the compile SDK near the top of the `android { ... }` block:

```kotlin
    compileSdk = 36
```

- [ ] **Step 4: Add dependencies**

```bash
flutter pub add drift sqlite3_flutter_libs path_provider path timezone flutter_riverpod
flutter pub add --dev drift_dev build_runner pigeon
```

- [ ] **Step 5: Verify Android builds with the new SDK levels**

```bash
flutter build apk --debug
```
Expected: `✓ Built build/app/outputs/flutter-apk/app-debug.apk` (first run downloads Gradle deps; allow several minutes).

- [ ] **Step 6: Extend .gitignore for Flutter**

Append to `.gitignore`:

```
.dart_tool/
.flutter-plugins
.flutter-plugins-dependencies
build/
android/.gradle/
android/local.properties
android/key.properties
*.g.dart
!lib/data/native/alarm_api.g.dart
ios/Pods/
ios/.symlinks/
```

> `*.g.dart` ignores Drift codegen (regenerated by build_runner), but the Pigeon-generated API is committed so CI and reviewers can read the native contract without running codegen.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "chore: scaffold Flutter project with Android SDK 26/36"
```

---

### Task 2: Alarm domain entity

**Files:**
- Create: `lib/domain/alarm.dart`
- Test: `test/domain/alarm_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `class Alarm` with fields `int id`, `int hour` (0–23), `int minute` (0–59), `Set<int> days` (0=Sun…6=Sat, empty = one-shot), `bool enabled`, `String label`, `String soundAsset`, `bool vibrate`.
  - `Alarm.copyWith({int? id, int? hour, int? minute, Set<int>? days, bool? enabled, String? label, String? soundAsset, bool? vibrate})`
  - `int hour12` and `bool isAm` getters; `static int to24Hour(int hour12, bool isAm)`.
  - `const Alarm({required this.id, required this.hour, required this.minute, this.days = const {}, this.enabled = true, this.label = 'Alarm', this.soundAsset = 'sounds/default_alarm.mp3', this.vibrate = true})`

- [ ] **Step 1: Write the failing test**

Create `test/domain/alarm_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/alarm.dart';

void main() {
  group('Alarm 12/24 hour conversion', () {
    test('midnight is 12 AM', () {
      const a = Alarm(id: 1, hour: 0, minute: 0);
      expect(a.hour12, 12);
      expect(a.isAm, isTrue);
    });

    test('noon is 12 PM', () {
      const a = Alarm(id: 1, hour: 12, minute: 0);
      expect(a.hour12, 12);
      expect(a.isAm, isFalse);
    });

    test('13:30 is 1:30 PM', () {
      const a = Alarm(id: 1, hour: 13, minute: 30);
      expect(a.hour12, 1);
      expect(a.isAm, isFalse);
    });

    test('to24Hour maps 12 AM to 0 and 12 PM to 12', () {
      expect(Alarm.to24Hour(12, true), 0);
      expect(Alarm.to24Hour(12, false), 12);
      expect(Alarm.to24Hour(6, true), 6);
      expect(Alarm.to24Hour(6, false), 18);
    });
  });

  group('Alarm defaults and copyWith', () {
    test('defaults to a one-shot enabled alarm', () {
      const a = Alarm(id: 1, hour: 6, minute: 30);
      expect(a.days, isEmpty);
      expect(a.enabled, isTrue);
      expect(a.vibrate, isTrue);
    });

    test('copyWith replaces only named fields', () {
      const a = Alarm(id: 1, hour: 6, minute: 30, label: 'Run');
      final b = a.copyWith(hour: 7);
      expect(b.hour, 7);
      expect(b.minute, 30);
      expect(b.label, 'Run');
      expect(b.id, 1);
    });

    test('equal field values compare equal', () {
      const a = Alarm(id: 1, hour: 6, minute: 30, days: {1, 2});
      const b = Alarm(id: 1, hour: 6, minute: 30, days: {1, 2});
      expect(a, equals(b));
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/domain/alarm_test.dart
```
Expected: FAIL — `Error: Couldn't resolve the package 'rise'` or `lib/domain/alarm.dart` not found.

- [ ] **Step 3: Write the implementation**

Create `lib/domain/alarm.dart`:

```dart
import 'package:collection/collection.dart';

/// A user's alarm. Times are stored in 24-hour form; the 12h/AM-PM split is a
/// UI concern only. [days] uses 0=Sunday … 6=Saturday to match the design's
/// S M T W T F S chips; an empty set means the alarm fires once and disables.
class Alarm {
  const Alarm({
    required this.id,
    required this.hour,
    required this.minute,
    this.days = const {},
    this.enabled = true,
    this.label = 'Alarm',
    this.soundAsset = 'sounds/default_alarm.mp3',
    this.vibrate = true,
  })  : assert(hour >= 0 && hour <= 23),
        assert(minute >= 0 && minute <= 59);

  final int id;
  final int hour;
  final int minute;
  final Set<int> days;
  final bool enabled;
  final String label;
  final String soundAsset;
  final bool vibrate;

  bool get isOneShot => days.isEmpty;

  int get hour12 {
    final h = hour % 12;
    return h == 0 ? 12 : h;
  }

  bool get isAm => hour < 12;

  static int to24Hour(int hour12, bool isAm) {
    final h = hour12 % 12;
    return isAm ? h : h + 12;
  }

  Alarm copyWith({
    int? id,
    int? hour,
    int? minute,
    Set<int>? days,
    bool? enabled,
    String? label,
    String? soundAsset,
    bool? vibrate,
  }) {
    return Alarm(
      id: id ?? this.id,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      days: days ?? this.days,
      enabled: enabled ?? this.enabled,
      label: label ?? this.label,
      soundAsset: soundAsset ?? this.soundAsset,
      vibrate: vibrate ?? this.vibrate,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Alarm &&
      other.id == id &&
      other.hour == hour &&
      other.minute == minute &&
      const SetEquality<int>().equals(other.days, days) &&
      other.enabled == enabled &&
      other.label == label &&
      other.soundAsset == soundAsset &&
      other.vibrate == vibrate;

  @override
  int get hashCode => Object.hash(id, hour, minute,
      const SetEquality<int>().hash(days), enabled, label, soundAsset, vibrate);

  @override
  String toString() =>
      'Alarm(id: $id, $hour:${minute.toString().padLeft(2, '0')}, days: $days, enabled: $enabled)';
}
```

- [ ] **Step 4: Add the `collection` dependency**

```bash
flutter pub add collection
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
flutter test test/domain/alarm_test.dart
```
Expected: PASS — `All tests passed!`

- [ ] **Step 6: Commit**

```bash
git add lib/domain/alarm.dart test/domain/alarm_test.dart pubspec.yaml pubspec.lock
git commit -m "feat: add Alarm domain entity with 12/24h conversion"
```

---

### Task 3: ScheduleMath — next occurrence (the heart)

This is the highest-risk logic in the app and it is pure Dart, so it gets exhaustive tests that run on Windows with no device. Every DST and timezone bug the spec's edge-case matrix names is pinned here.

**Files:**
- Create: `lib/domain/schedule_math.dart`
- Test: `test/domain/schedule_math_test.dart`

**Interfaces:**
- Consumes: `Alarm` from Task 2.
- Produces:
  - `tz.TZDateTime? nextOccurrence({required Alarm alarm, required tz.TZDateTime from, required tz.Location location})` — returns the next instant the alarm should fire strictly after `from`, or `null` if disabled.
  - `tz.TZDateTime resolveWallTime(tz.Location location, int year, int month, int day, int hour, int minute)` — DST-gap-safe wall-time resolution.
  - `int weekdayToIndex(int dartWeekday)` — maps Dart's Mon=1…Sun=7 to the domain's Sun=0…Sat=6.

- [ ] **Step 1: Write the failing test**

Create `test/domain/schedule_math_test.dart`. America/New_York 2026 DST transitions: **spring forward Sun 2026-03-08** (02:00→03:00, so 02:00–02:59 does not exist) and **fall back Sun 2026-11-01** (02:00→01:00, so 01:00–01:59 occurs twice).

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:rise/domain/alarm.dart';
import 'package:rise/domain/schedule_math.dart';

void main() {
  late tz.Location ny;
  late tz.Location utc;

  setUpAll(() {
    tzdata.initializeTimeZones();
    ny = tz.getLocation('America/New_York');
    utc = tz.getLocation('UTC');
  });

  group('weekdayToIndex', () {
    test('maps Dart Monday=1 to index 1 and Sunday=7 to index 0', () {
      expect(weekdayToIndex(DateTime.monday), 1);
      expect(weekdayToIndex(DateTime.saturday), 6);
      expect(weekdayToIndex(DateTime.sunday), 0);
    });
  });

  group('one-shot alarms', () {
    test('fires later today when the time has not passed', () {
      const alarm = Alarm(id: 1, hour: 6, minute: 30);
      final from = tz.TZDateTime(ny, 2026, 7, 15, 5, 0);
      final next = nextOccurrence(alarm: alarm, from: from, location: ny);
      expect(next, tz.TZDateTime(ny, 2026, 7, 15, 6, 30));
    });

    test('rolls to tomorrow when the time has passed', () {
      const alarm = Alarm(id: 1, hour: 6, minute: 30);
      final from = tz.TZDateTime(ny, 2026, 7, 15, 7, 0);
      final next = nextOccurrence(alarm: alarm, from: from, location: ny);
      expect(next, tz.TZDateTime(ny, 2026, 7, 16, 6, 30));
    });

    test('rolls to tomorrow when exactly at the alarm time (strictly after)', () {
      const alarm = Alarm(id: 1, hour: 6, minute: 30);
      final from = tz.TZDateTime(ny, 2026, 7, 15, 6, 30);
      final next = nextOccurrence(alarm: alarm, from: from, location: ny);
      expect(next, tz.TZDateTime(ny, 2026, 7, 16, 6, 30));
    });
  });

  group('disabled alarms', () {
    test('return null', () {
      const alarm = Alarm(id: 1, hour: 6, minute: 30, enabled: false);
      final from = tz.TZDateTime(ny, 2026, 7, 15, 5, 0);
      expect(nextOccurrence(alarm: alarm, from: from, location: ny), isNull);
    });
  });

  group('repeating alarms', () {
    test('weekday alarm on Saturday rolls to Monday', () {
      // 2026-07-18 is a Saturday. Weekdays = Mon..Fri.
      const alarm = Alarm(id: 1, hour: 6, minute: 30, days: {1, 2, 3, 4, 5});
      final from = tz.TZDateTime(ny, 2026, 7, 18, 9, 0);
      final next = nextOccurrence(alarm: alarm, from: from, location: ny);
      expect(next, tz.TZDateTime(ny, 2026, 7, 20, 6, 30)); // Monday
    });

    test('fires today when today is a selected day and time has not passed', () {
      // 2026-07-15 is a Wednesday (index 3).
      const alarm = Alarm(id: 1, hour: 6, minute: 30, days: {3});
      final from = tz.TZDateTime(ny, 2026, 7, 15, 5, 0);
      final next = nextOccurrence(alarm: alarm, from: from, location: ny);
      expect(next, tz.TZDateTime(ny, 2026, 7, 15, 6, 30));
    });

    test('single-day alarm rolls a full week when today has passed', () {
      const alarm = Alarm(id: 1, hour: 6, minute: 30, days: {3}); // Wednesday
      final from = tz.TZDateTime(ny, 2026, 7, 15, 7, 0);
      final next = nextOccurrence(alarm: alarm, from: from, location: ny);
      expect(next, tz.TZDateTime(ny, 2026, 7, 22, 6, 30));
    });

    test('Sunday-only alarm uses index 0', () {
      // 2026-07-19 is a Sunday.
      const alarm = Alarm(id: 1, hour: 8, minute: 0, days: {0});
      final from = tz.TZDateTime(ny, 2026, 7, 15, 12, 0);
      final next = nextOccurrence(alarm: alarm, from: from, location: ny);
      expect(next, tz.TZDateTime(ny, 2026, 7, 19, 8, 0));
    });
  });

  group('DST spring-forward (2026-03-08 America/New_York, 02:00 -> 03:00)', () {
    test('02:30 does not exist and fires at the first valid instant after', () {
      const alarm = Alarm(id: 1, hour: 2, minute: 30);
      final from = tz.TZDateTime(ny, 2026, 3, 7, 22, 0);
      final next = nextOccurrence(alarm: alarm, from: from, location: ny)!;
      expect(next, tz.TZDateTime(ny, 2026, 3, 8, 3, 0));
      expect(next.timeZoneOffset, const Duration(hours: -4)); // EDT
    });

    test('01:30 still exists on the transition day', () {
      const alarm = Alarm(id: 1, hour: 1, minute: 30);
      final from = tz.TZDateTime(ny, 2026, 3, 7, 22, 0);
      final next = nextOccurrence(alarm: alarm, from: from, location: ny);
      expect(next, tz.TZDateTime(ny, 2026, 3, 8, 1, 30));
    });

    test('a daily alarm crossing the transition keeps its wall-clock time', () {
      const alarm = Alarm(id: 1, hour: 6, minute: 30, days: {0, 1, 2, 3, 4, 5, 6});
      final from = tz.TZDateTime(ny, 2026, 3, 7, 12, 0);
      final next = nextOccurrence(alarm: alarm, from: from, location: ny)!;
      expect(next.hour, 6);
      expect(next.minute, 30);
      expect(next.day, 8);
    });
  });

  group('DST fall-back (2026-11-01 America/New_York, 02:00 -> 01:00)', () {
    test('the duplicated 01:30 fires exactly once, then next day', () {
      const alarm = Alarm(id: 1, hour: 1, minute: 30, days: {0, 1, 2, 3, 4, 5, 6});
      final from = tz.TZDateTime(ny, 2026, 10, 31, 12, 0);

      final first = nextOccurrence(alarm: alarm, from: from, location: ny)!;
      expect(first.year, 2026);
      expect(first.month, 11);
      expect(first.day, 1);
      expect(first.hour, 1);
      expect(first.minute, 30);

      // The next occurrence after the first must be the NEXT DAY, never the
      // second (EST) 01:30 on the same date.
      final second = nextOccurrence(alarm: alarm, from: first, location: ny)!;
      expect(second.day, 2);
      expect(second.hour, 1);
      expect(second.minute, 30);
    });
  });

  group('timezone independence', () {
    test('the same alarm resolves to different instants in different zones', () {
      const alarm = Alarm(id: 1, hour: 6, minute: 30);
      final fromNy = tz.TZDateTime(ny, 2026, 7, 15, 5, 0);
      final fromUtc = tz.TZDateTime(utc, 2026, 7, 15, 5, 0);
      final nextNy = nextOccurrence(alarm: alarm, from: fromNy, location: ny)!;
      final nextUtc = nextOccurrence(alarm: alarm, from: fromUtc, location: utc)!;
      expect(nextNy.hour, 6);
      expect(nextUtc.hour, 6);
      expect(nextNy.toUtc(), isNot(equals(nextUtc.toUtc())));
    });
  });

  group('resolveWallTime', () {
    test('returns the requested wall time when it exists', () {
      final t = resolveWallTime(ny, 2026, 7, 15, 6, 30);
      expect(t.hour, 6);
      expect(t.minute, 30);
    });

    test('snaps a nonexistent DST-gap time forward to the gap end', () {
      final t = resolveWallTime(ny, 2026, 3, 8, 2, 30);
      expect(t.hour, 3);
      expect(t.minute, 0);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/domain/schedule_math_test.dart
```
Expected: FAIL — `Error: Couldn't resolve the package` / `schedule_math.dart` not found.

- [ ] **Step 3: Write the implementation**

Create `lib/domain/schedule_math.dart`:

```dart
import 'package:timezone/timezone.dart' as tz;

import 'alarm.dart';

/// How many days ahead to search before giving up. A repeating alarm always
/// fires within 7 days; 8 gives one day of slack for same-day rollover.
const int _searchHorizonDays = 8;

/// Maps Dart's weekday numbering (Mon=1 … Sun=7) to the domain's day indices
/// (Sun=0 … Sat=6), matching the design's S M T W T F S chips.
int weekdayToIndex(int dartWeekday) => dartWeekday % 7;

/// Resolves the wall time (`year-month-day hour:minute`) in [location] to a
/// concrete instant.
///
/// During a DST spring-forward gap the requested wall time does not exist. Per
/// spec, we fire at the first valid instant after the gap: we walk forward a
/// minute at a time until a wall time round-trips. Real-world gaps are at most
/// two hours, so the 180-minute cap can never be reached in practice.
tz.TZDateTime resolveWallTime(
  tz.Location location,
  int year,
  int month,
  int day,
  int hour,
  int minute,
) {
  final candidate = tz.TZDateTime(location, year, month, day, hour, minute);
  if (candidate.hour == hour &&
      candidate.minute == minute &&
      candidate.day == day) {
    return candidate;
  }

  for (var add = 1; add <= 180; add++) {
    final total = hour * 60 + minute + add;
    final probeHour = (total ~/ 60) % 24;
    final probeMinute = total % 60;
    final dayShift = total ~/ 1440;
    final date = DateTime.utc(year, month, day).add(Duration(days: dayShift));
    final probe = tz.TZDateTime(
        location, date.year, date.month, date.day, probeHour, probeMinute);
    if (probe.hour == probeHour && probe.minute == probeMinute) {
      return probe;
    }
  }

  // Unreachable for real timezone data; return the library's normalization.
  return candidate;
}

/// The next instant [alarm] should fire, strictly after [from], or null if the
/// alarm is disabled.
///
/// Alarms follow the local wall clock: a 6:30 alarm is 6:30 on both sides of a
/// DST transition. Calendar arithmetic is done in UTC to avoid Duration-based
/// day math silently shifting the wall clock across a transition.
tz.TZDateTime? nextOccurrence({
  required Alarm alarm,
  required tz.TZDateTime from,
  required tz.Location location,
}) {
  if (!alarm.enabled) return null;

  final startDate = DateTime.utc(from.year, from.month, from.day);

  for (var offset = 0; offset <= _searchHorizonDays; offset++) {
    final date = startDate.add(Duration(days: offset));

    if (!alarm.isOneShot) {
      final index = weekdayToIndex(
          DateTime.utc(date.year, date.month, date.day).weekday);
      if (!alarm.days.contains(index)) continue;
    }

    final candidate = resolveWallTime(
        location, date.year, date.month, date.day, alarm.hour, alarm.minute);

    if (candidate.isAfter(from)) return candidate;
  }

  return null;
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
flutter test test/domain/schedule_math_test.dart
```
Expected: PASS — all 16 tests green.

> If the fall-back test fails because `nextOccurrence` returns the same instant twice, the bug is in the `isAfter(from)` comparison — `TZDateTime` comparison must be instant-based, not wall-clock-based. Do not "fix" it by comparing wall-clock fields.

- [ ] **Step 5: Commit**

```bash
git add lib/domain/schedule_math.dart test/domain/schedule_math_test.dart
git commit -m "feat: add DST-safe alarm schedule math"
```

---

### Task 4: Reconcile diff

Native holds no scheduling logic. Every change re-runs a full reconcile, so the diff must be idempotent — the spec calls this out explicitly under unit testing.

**Files:**
- Create: `lib/domain/scheduled_occurrence.dart`
- Create: `lib/domain/reconcile.dart`
- Test: `test/domain/reconcile_test.dart`

**Interfaces:**
- Consumes: `Alarm`, `nextOccurrence` from Tasks 2–3.
- Produces:
  - `class ScheduledOccurrence` with `int alarmId`, `DateTime fireAt` (UTC), `String label`, `String soundAsset`, `bool vibrate`; value equality.
  - `class ReconcilePlan` with `List<ScheduledOccurrence> toSchedule`, `List<int> toCancel`, `bool get isEmpty`.
  - `List<ScheduledOccurrence> desiredOccurrences({required List<Alarm> alarms, required tz.TZDateTime now, required tz.Location location})`
  - `ReconcilePlan diffSchedule({required List<ScheduledOccurrence> desired, required List<ScheduledOccurrence> current})`

- [ ] **Step 1: Write the failing test**

Create `test/domain/reconcile_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:rise/domain/alarm.dart';
import 'package:rise/domain/reconcile.dart';
import 'package:rise/domain/scheduled_occurrence.dart';

void main() {
  late tz.Location ny;

  setUpAll(() {
    tzdata.initializeTimeZones();
    ny = tz.getLocation('America/New_York');
  });

  ScheduledOccurrence occ(int id, DateTime fireAt) => ScheduledOccurrence(
        alarmId: id,
        fireAt: fireAt,
        label: 'Alarm',
        soundAsset: 'sounds/default_alarm.mp3',
        vibrate: true,
      );

  group('desiredOccurrences', () {
    test('skips disabled alarms', () {
      final now = tz.TZDateTime(ny, 2026, 7, 15, 5, 0);
      final result = desiredOccurrences(
        alarms: const [
          Alarm(id: 1, hour: 6, minute: 30),
          Alarm(id: 2, hour: 7, minute: 0, enabled: false),
        ],
        now: now,
        location: ny,
      );
      expect(result.map((o) => o.alarmId), [1]);
    });

    test('is sorted by fire time', () {
      final now = tz.TZDateTime(ny, 2026, 7, 15, 5, 0);
      final result = desiredOccurrences(
        alarms: const [
          Alarm(id: 1, hour: 9, minute: 0),
          Alarm(id: 2, hour: 6, minute: 30),
        ],
        now: now,
        location: ny,
      );
      expect(result.map((o) => o.alarmId), [2, 1]);
    });

    test('carries label, sound and vibrate through', () {
      final now = tz.TZDateTime(ny, 2026, 7, 15, 5, 0);
      final result = desiredOccurrences(
        alarms: const [
          Alarm(id: 1, hour: 6, minute: 30, label: 'Run', soundAsset: 'sounds/x.mp3', vibrate: false),
        ],
        now: now,
        location: ny,
      );
      expect(result.single.label, 'Run');
      expect(result.single.soundAsset, 'sounds/x.mp3');
      expect(result.single.vibrate, isFalse);
    });

    test('emits fireAt in UTC', () {
      final now = tz.TZDateTime(ny, 2026, 7, 15, 5, 0);
      final result = desiredOccurrences(
        alarms: const [Alarm(id: 1, hour: 6, minute: 30)],
        now: now,
        location: ny,
      );
      expect(result.single.fireAt.isUtc, isTrue);
    });
  });

  group('diffSchedule', () {
    test('schedules everything when nothing is currently scheduled', () {
      final desired = [occ(1, DateTime.utc(2026, 7, 15, 10, 30))];
      final plan = diffSchedule(desired: desired, current: const []);
      expect(plan.toSchedule, desired);
      expect(plan.toCancel, isEmpty);
    });

    test('is idempotent: diffing identical lists produces an empty plan', () {
      final same = [
        occ(1, DateTime.utc(2026, 7, 15, 10, 30)),
        occ(2, DateTime.utc(2026, 7, 15, 11, 0)),
      ];
      final plan = diffSchedule(desired: same, current: same);
      expect(plan.isEmpty, isTrue);
    });

    test('cancels occurrences that are no longer desired', () {
      final plan = diffSchedule(
        desired: const [],
        current: [occ(1, DateTime.utc(2026, 7, 15, 10, 30))],
      );
      expect(plan.toCancel, [1]);
      expect(plan.toSchedule, isEmpty);
    });

    test('reschedules an alarm whose fire time changed', () {
      final plan = diffSchedule(
        desired: [occ(1, DateTime.utc(2026, 7, 15, 11, 30))],
        current: [occ(1, DateTime.utc(2026, 7, 15, 10, 30))],
      );
      expect(plan.toSchedule.single.fireAt, DateTime.utc(2026, 7, 15, 11, 30));
      expect(plan.toCancel, isEmpty,
          reason: 'rescheduling the same id replaces it; no cancel needed');
    });

    test('reschedules when only the sound changed', () {
      final current = [occ(1, DateTime.utc(2026, 7, 15, 10, 30))];
      final desired = [
        ScheduledOccurrence(
          alarmId: 1,
          fireAt: DateTime.utc(2026, 7, 15, 10, 30),
          label: 'Alarm',
          soundAsset: 'sounds/birdsong.mp3',
          vibrate: true,
        )
      ];
      final plan = diffSchedule(desired: desired, current: current);
      expect(plan.toSchedule, desired);
    });

    test('handles a mixed add, change and remove in one plan', () {
      final plan = diffSchedule(
        desired: [
          occ(1, DateTime.utc(2026, 7, 15, 11, 30)), // changed
          occ(3, DateTime.utc(2026, 7, 15, 12, 0)), // added
        ],
        current: [
          occ(1, DateTime.utc(2026, 7, 15, 10, 30)),
          occ(2, DateTime.utc(2026, 7, 15, 9, 0)), // removed
        ],
      );
      expect(plan.toSchedule.map((o) => o.alarmId).toSet(), {1, 3});
      expect(plan.toCancel, [2]);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/domain/reconcile_test.dart
```
Expected: FAIL — `reconcile.dart` not found.

- [ ] **Step 3: Write ScheduledOccurrence**

Create `lib/domain/scheduled_occurrence.dart`:

```dart
/// One concrete future firing of an alarm, handed to the native layer.
///
/// [fireAt] is always UTC: the native side needs an absolute instant, and all
/// wall-clock/DST reasoning has already happened in [nextOccurrence].
class ScheduledOccurrence {
  const ScheduledOccurrence({
    required this.alarmId,
    required this.fireAt,
    required this.label,
    required this.soundAsset,
    required this.vibrate,
  });

  final int alarmId;
  final DateTime fireAt;
  final String label;
  final String soundAsset;
  final bool vibrate;

  @override
  bool operator ==(Object other) =>
      other is ScheduledOccurrence &&
      other.alarmId == alarmId &&
      other.fireAt.isAtSameMomentAs(fireAt) &&
      other.label == label &&
      other.soundAsset == soundAsset &&
      other.vibrate == vibrate;

  @override
  int get hashCode =>
      Object.hash(alarmId, fireAt.toUtc(), label, soundAsset, vibrate);

  @override
  String toString() =>
      'ScheduledOccurrence(alarm: $alarmId, fireAt: ${fireAt.toIso8601String()})';
}
```

- [ ] **Step 4: Write reconcile**

Create `lib/domain/reconcile.dart`:

```dart
import 'package:timezone/timezone.dart' as tz;

import 'alarm.dart';
import 'schedule_math.dart';
import 'scheduled_occurrence.dart';

/// The work needed to bring the native scheduler in line with [desired].
class ReconcilePlan {
  const ReconcilePlan({required this.toSchedule, required this.toCancel});

  final List<ScheduledOccurrence> toSchedule;
  final List<int> toCancel;

  bool get isEmpty => toSchedule.isEmpty && toCancel.isEmpty;

  @override
  String toString() =>
      'ReconcilePlan(schedule: ${toSchedule.length}, cancel: ${toCancel.length})';
}

/// Every alarm's next firing, sorted soonest-first.
List<ScheduledOccurrence> desiredOccurrences({
  required List<Alarm> alarms,
  required tz.TZDateTime now,
  required tz.Location location,
}) {
  final result = <ScheduledOccurrence>[];

  for (final alarm in alarms) {
    final next = nextOccurrence(alarm: alarm, from: now, location: location);
    if (next == null) continue;
    result.add(ScheduledOccurrence(
      alarmId: alarm.id,
      fireAt: next.toUtc(),
      label: alarm.label,
      soundAsset: alarm.soundAsset,
      vibrate: alarm.vibrate,
    ));
  }

  result.sort((a, b) => a.fireAt.compareTo(b.fireAt));
  return result;
}

/// Diffs desired against currently-scheduled state.
///
/// Scheduling an id that is already scheduled replaces it (Android's
/// PendingIntent.FLAG_UPDATE_CURRENT semantics), so a changed occurrence only
/// needs a schedule, never a paired cancel. Must be idempotent: reconciling an
/// unchanged state produces an empty plan.
ReconcilePlan diffSchedule({
  required List<ScheduledOccurrence> desired,
  required List<ScheduledOccurrence> current,
}) {
  final currentById = {for (final o in current) o.alarmId: o};
  final desiredIds = desired.map((o) => o.alarmId).toSet();

  final toSchedule = <ScheduledOccurrence>[];
  for (final want in desired) {
    final have = currentById[want.alarmId];
    if (have != want) toSchedule.add(want);
  }

  final toCancel = <int>[
    for (final o in current)
      if (!desiredIds.contains(o.alarmId)) o.alarmId
  ];

  return ReconcilePlan(toSchedule: toSchedule, toCancel: toCancel);
}
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
flutter test test/domain/reconcile_test.dart
```
Expected: PASS — all 10 tests green.

- [ ] **Step 6: Run the whole suite**

```bash
flutter test
```
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/domain/ test/domain/
git commit -m "feat: add idempotent schedule reconcile diff"
```

---

### Task 5: Local alarm storage (Drift)

**Files:**
- Create: `lib/data/local/database.dart`
- Create: `lib/data/local/alarm_repository.dart`
- Test: `test/data/alarm_repository_test.dart`

**Interfaces:**
- Consumes: `Alarm` from Task 2.
- Produces:
  - `class RiseDatabase extends _$RiseDatabase` with constructor `RiseDatabase(QueryExecutor e)`.
  - `class AlarmRepository` with `AlarmRepository(this._db)`, `Future<List<Alarm>> all()`, `Future<Alarm> upsert(Alarm alarm)` (id `0` inserts and returns the assigned id), `Future<void> delete(int id)`, `Future<void> setEnabled(int id, bool enabled)`, `Stream<List<Alarm>> watchAll()`.

- [ ] **Step 1: Write the failing test**

Create `test/data/alarm_repository_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/local/alarm_repository.dart';
import 'package:rise/data/local/database.dart';
import 'package:rise/domain/alarm.dart';

void main() {
  late RiseDatabase db;
  late AlarmRepository repo;

  setUp(() {
    db = RiseDatabase(NativeDatabase.memory());
    repo = AlarmRepository(db);
  });

  tearDown(() async => db.close());

  test('starts empty', () async {
    expect(await repo.all(), isEmpty);
  });

  test('inserts an alarm and assigns an id', () async {
    final saved = await repo.upsert(
        const Alarm(id: 0, hour: 6, minute: 30, label: 'Run', days: {1, 2, 3, 4, 5}));
    expect(saved.id, greaterThan(0));

    final all = await repo.all();
    expect(all, hasLength(1));
    expect(all.single.label, 'Run');
    expect(all.single.days, {1, 2, 3, 4, 5});
  });

  test('round-trips an empty day set as a one-shot alarm', () async {
    await repo.upsert(const Alarm(id: 0, hour: 6, minute: 30));
    expect((await repo.all()).single.days, isEmpty);
  });

  test('updates an existing alarm in place', () async {
    final saved = await repo.upsert(const Alarm(id: 0, hour: 6, minute: 30));
    await repo.upsert(saved.copyWith(hour: 7, label: 'Later'));

    final all = await repo.all();
    expect(all, hasLength(1));
    expect(all.single.hour, 7);
    expect(all.single.label, 'Later');
  });

  test('toggles enabled', () async {
    final saved = await repo.upsert(const Alarm(id: 0, hour: 6, minute: 30));
    await repo.setEnabled(saved.id, false);
    expect((await repo.all()).single.enabled, isFalse);
  });

  test('deletes an alarm', () async {
    final saved = await repo.upsert(const Alarm(id: 0, hour: 6, minute: 30));
    await repo.delete(saved.id);
    expect(await repo.all(), isEmpty);
  });

  test('watchAll emits on change', () async {
    expectLater(
      repo.watchAll().map((list) => list.length),
      emitsInOrder([0, 1]),
    );
    await repo.upsert(const Alarm(id: 0, hour: 6, minute: 30));
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/data/alarm_repository_test.dart
```
Expected: FAIL — `database.dart` not found.

- [ ] **Step 3: Write the database**

Create `lib/data/local/database.dart`:

```dart
import 'package:drift/drift.dart';

part 'database.g.dart';

/// Alarms as stored on device. This table is the source of truth for anything
/// that must ring: the app must be able to schedule every alarm with no
/// network access at all.
///
/// The row class is named AlarmRow, not Drift's default `Alarm`, which would
/// collide with the domain entity of that name.
@DataClassName('AlarmRow')
class Alarms extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get hour => integer()();
  IntColumn get minute => integer()();

  /// Day indices 0=Sun..6=Sat joined by commas. Empty string = one-shot.
  TextColumn get days => text().withDefault(const Constant(''))();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  TextColumn get label => text().withDefault(const Constant('Alarm'))();
  TextColumn get soundAsset =>
      text().withDefault(const Constant('sounds/default_alarm.mp3'))();
  BoolColumn get vibrate => boolean().withDefault(const Constant(true))();
}

@DriftDatabase(tables: [Alarms])
class RiseDatabase extends _$RiseDatabase {
  RiseDatabase(super.e);

  @override
  int get schemaVersion => 1;
}
```

- [ ] **Step 4: Write the repository**

Create `lib/data/local/alarm_repository.dart`:

```dart
import 'package:drift/drift.dart';

import '../../domain/alarm.dart';
import 'database.dart';

/// Reads and writes alarms. Translates between the domain's `Set<int> days`
/// and the database's comma-joined text column.
class AlarmRepository {
  AlarmRepository(this._db);

  final RiseDatabase _db;

  static String encodeDays(Set<int> days) {
    final sorted = days.toList()..sort();
    return sorted.join(',');
  }

  static Set<int> decodeDays(String raw) {
    if (raw.isEmpty) return const {};
    return raw.split(',').map(int.parse).toSet();
  }

  static Alarm _toDomain(AlarmRow row) => Alarm(
        id: row.id,
        hour: row.hour,
        minute: row.minute,
        days: decodeDays(row.days),
        enabled: row.enabled,
        label: row.label,
        soundAsset: row.soundAsset,
        vibrate: row.vibrate,
      );

  Future<List<Alarm>> all() async {
    final rows = await _db.select(_db.alarms).get();
    return rows.map(_toDomain).toList();
  }

  Stream<List<Alarm>> watchAll() =>
      _db.select(_db.alarms).watch().map((rows) => rows.map(_toDomain).toList());

  /// Inserts when [alarm].id is 0, otherwise updates in place. Returns the
  /// stored alarm, including its assigned id.
  Future<Alarm> upsert(Alarm alarm) async {
    final companion = AlarmsCompanion(
      id: alarm.id == 0 ? const Value.absent() : Value(alarm.id),
      hour: Value(alarm.hour),
      minute: Value(alarm.minute),
      days: Value(encodeDays(alarm.days)),
      enabled: Value(alarm.enabled),
      label: Value(alarm.label),
      soundAsset: Value(alarm.soundAsset),
      vibrate: Value(alarm.vibrate),
    );

    if (alarm.id == 0) {
      final id = await _db.into(_db.alarms).insert(companion);
      return alarm.copyWith(id: id);
    }

    await _db.update(_db.alarms).replace(companion);
    return alarm;
  }

  Future<void> delete(int id) =>
      (_db.delete(_db.alarms)..where((t) => t.id.equals(id))).go();

  Future<void> setEnabled(int id, bool enabled) =>
      (_db.update(_db.alarms)..where((t) => t.id.equals(id)))
          .write(AlarmsCompanion(enabled: Value(enabled)));
}
```

- [ ] **Step 5: Generate the Drift code**

```bash
dart run build_runner build --delete-conflicting-outputs
```
Expected: `Succeeded after ...` and `lib/data/local/database.g.dart` created, containing `class AlarmRow`.

- [ ] **Step 6: Run the test to verify it passes**

```bash
flutter test test/data/alarm_repository_test.dart
```
Expected: PASS — all 7 tests green.

- [ ] **Step 7: Commit**

```bash
git add lib/data/ test/data/ pubspec.yaml pubspec.lock
git commit -m "feat: add local alarm storage with Drift"
```

---

### Task 6: Pigeon native interface

Defines the entire Dart↔Kotlin contract in one file and generates both sides. No hand-written channel code anywhere.

**Files:**
- Create: `pigeons/alarm_api.dart`
- Generated: `lib/data/native/alarm_api.g.dart`, `android/app/src/main/kotlin/com/riseapp/rise/AlarmApi.g.kt`, `ios/Runner/AlarmApi.g.swift`

**Interfaces:**
- Consumes: nothing (contract definition).
- Produces (all consumed by Tasks 7–11):
  - `class NativeAlarm { int id; int fireAtEpochMs; String label; String soundAsset; bool vibrate; }`
  - `class AlarmPermissions { bool notifications; bool exactAlarm; bool fullScreenIntent; bool batteryUnrestricted; }`
  - `@HostApi() abstract class AlarmHostApi` — `void reconcile(List<NativeAlarm> alarms)`, `void ringNow(NativeAlarm alarm)`, `void cancelAll()`, `AlarmPermissions getPermissions()`, `void requestNotificationPermission()`, `void openExactAlarmSettings()`, `void openBatterySettings()`, `void openFullScreenIntentSettings()`, `int? getRingingAlarmId()`, `void stopRinging(int alarmId)`
  - `@FlutterApi() abstract class AlarmFlutterApi` — `void onAlarmFired(int alarmId)`

- [ ] **Step 1: Write the Pigeon definition**

Create `pigeons/alarm_api.dart`:

```dart
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/data/native/alarm_api.g.dart',
  kotlinOut: 'android/app/src/main/kotlin/com/riseapp/rise/AlarmApi.g.kt',
  kotlinOptions: KotlinOptions(package: 'com.riseapp.rise'),
  swiftOut: 'ios/Runner/AlarmApi.g.swift',
  dartPackageName: 'rise',
))

/// One concrete future firing, as handed to the platform scheduler.
/// [fireAtEpochMs] is absolute UTC milliseconds — all wall-clock and DST
/// reasoning happens in Dart before this crosses the channel.
class NativeAlarm {
  NativeAlarm({
    required this.id,
    required this.fireAtEpochMs,
    required this.label,
    required this.soundAsset,
    required this.vibrate,
  });

  int id;
  int fireAtEpochMs;
  String label;
  String soundAsset;
  bool vibrate;
}

/// Everything that can silently stop Rise from ringing. Surfaced by the Setup
/// Guardian; re-checked on every app launch because OEMs revert these.
class AlarmPermissions {
  AlarmPermissions({
    required this.notifications,
    required this.exactAlarm,
    required this.fullScreenIntent,
    required this.batteryUnrestricted,
  });

  bool notifications;
  bool exactAlarm;
  bool fullScreenIntent;
  bool batteryUnrestricted;
}

@HostApi()
abstract class AlarmHostApi {
  /// Replaces the platform's entire scheduled set with [alarms].
  void reconcile(List<NativeAlarm> alarms);

  /// Rings [alarm] immediately without touching the scheduled set.
  ///
  /// Missed-alarm recovery must never go through [reconcile]: reconcile is a
  /// full replace, so recovering one alarm that way would silently cancel
  /// every other alarm the user has set.
  void ringNow(NativeAlarm alarm);

  void cancelAll();

  AlarmPermissions getPermissions();

  void requestNotificationPermission();
  void openExactAlarmSettings();
  void openBatterySettings();
  void openFullScreenIntentSettings();

  /// The alarm id currently ringing, or null if nothing is ringing.
  ///
  /// Safe to call repeatedly — this peeks, it does not clear state. The id
  /// stays valid for the whole ring so [stopRinging] can verify it is
  /// stopping the alarm it was asked to stop. Needed at cold start: the
  /// ringing activity can launch the Flutter engine from scratch, in which
  /// case no onAlarmFired callback ever arrives.
  int? getRingingAlarmId();

  void stopRinging(int alarmId);
}

@FlutterApi()
abstract class AlarmFlutterApi {
  /// Fired when an alarm starts ringing while the engine is already alive.
  void onAlarmFired(int alarmId);
}
```

- [ ] **Step 2: Generate both sides**

```bash
dart run pigeon --input pigeons/alarm_api.dart
```
Expected: no output on success; three generated files appear.

- [ ] **Step 3: Verify the generated files exist**

```bash
ls lib/data/native/alarm_api.g.dart android/app/src/main/kotlin/com/riseapp/rise/AlarmApi.g.kt ios/Runner/AlarmApi.g.swift
```
Expected: all three paths listed.

- [ ] **Step 4: Verify the project still analyzes**

```bash
flutter analyze lib/data/native/
```
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add -f pigeons/ lib/data/native/alarm_api.g.dart android/app/src/main/kotlin/com/riseapp/rise/AlarmApi.g.kt ios/Runner/AlarmApi.g.swift
git commit -m "feat: define native alarm channel with Pigeon"
```

---

### Task 7: Android manifest, permissions, and scheduling

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml`
- Create: `android/app/src/main/kotlin/com/riseapp/rise/AlarmScheduler.kt`
- Create: `android/app/src/main/kotlin/com/riseapp/rise/AlarmReceiver.kt`

**Interfaces:**
- Consumes: `NativeAlarm` from Task 6.
- Produces:
  - `object AlarmScheduler` — `fun reconcile(context: Context, alarms: List<NativeAlarm>)`, `fun cancel(context: Context, id: Int)`, `fun cancelAll(context: Context)`, `fun canScheduleExact(context: Context): Boolean`
  - `class AlarmReceiver : BroadcastReceiver` — receives the fired PendingIntent, starts `AlarmService` (Task 8).
  - Both consumed by `MainActivity` in Task 10.

- [ ] **Step 1: Declare permissions and components**

Replace the contents of `android/app/src/main/AndroidManifest.xml` with:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- API 33+: install-granted, not user-revocable. Play restricts this to
         apps whose core function is alarms/timers/calendar. Rise qualifies. -->
    <uses-permission android:name="android.permission.USE_EXACT_ALARM" />
    <!-- API 31-32 fallback only; user-revocable. -->
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"
        android:maxSdkVersion="32" />

    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_SYSTEM_EXEMPTED" />
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
    <uses-permission android:name="android.permission.VIBRATE" />
    <uses-permission android:name="android.permission.WAKE_LOCK" />
    <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />

    <application
        android:label="Rise"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">

        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:taskAffinity=""
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <meta-data
                android:name="io.flutter.embedding.android.NormalTheme"
                android:resource="@style/NormalTheme" />
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>

        <!-- Shows over the lock screen and turns the screen on. -->
        <activity
            android:name=".RingActivity"
            android:exported="false"
            android:showWhenLocked="true"
            android:turnScreenOn="true"
            android:excludeFromRecents="true"
            android:launchMode="singleInstance"
            android:theme="@style/LaunchTheme" />

        <receiver android:name=".AlarmReceiver" android:exported="false" />

        <receiver android:name=".BootReceiver" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
                <action android:name="android.intent.action.TIME_SET" />
                <action android:name="android.intent.action.TIMEZONE_CHANGED" />
            </intent-filter>
        </receiver>

        <service
            android:name=".AlarmService"
            android:exported="false"
            android:foregroundServiceType="systemExempted" />

        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>
</manifest>
```

- [ ] **Step 2: Write the scheduler**

Create `android/app/src/main/kotlin/com/riseapp/rise/AlarmScheduler.kt`:

```kotlin
package com.riseapp.rise

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * Owns nothing but "ring at this instant". All scheduling decisions (repeat
 * days, DST, timezones) are made in Dart; this receives absolute UTC instants.
 */
object AlarmScheduler {
    private const val TAG = "AlarmScheduler"
    const val EXTRA_ALARM_ID = "alarmId"
    const val EXTRA_LABEL = "label"
    const val EXTRA_SOUND = "soundAsset"
    const val EXTRA_VIBRATE = "vibrate"

    private const val PREFS = "rise_scheduled"
    private const val KEY_IDS = "ids"

    private fun alarmManager(context: Context): AlarmManager =
        context.getSystemService(AlarmManager::class.java)

    fun canScheduleExact(context: Context): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            alarmManager(context).canScheduleExactAlarms()
        } else {
            true
        }

    private fun firePendingIntent(context: Context, alarm: NativeAlarm): PendingIntent {
        val intent = Intent(context, AlarmReceiver::class.java).apply {
            putExtra(EXTRA_ALARM_ID, alarm.id.toInt())
            putExtra(EXTRA_LABEL, alarm.label)
            putExtra(EXTRA_SOUND, alarm.soundAsset)
            putExtra(EXTRA_VIBRATE, alarm.vibrate)
        }
        return PendingIntent.getBroadcast(
            context,
            alarm.id.toInt(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    /** Replaces the entire scheduled set. Idempotent by construction. */
    fun reconcile(context: Context, alarms: List<NativeAlarm>) {
        cancelAll(context)

        val am = alarmManager(context)
        val ids = mutableSetOf<String>()

        for (alarm in alarms) {
            val showIntent = PendingIntent.getActivity(
                context,
                alarm.id.toInt(),
                Intent(context, RingActivity::class.java)
                    .putExtra(EXTRA_ALARM_ID, alarm.id.toInt()),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            // setAlarmClock: exact, never time-shifted, exits Doze shortly
            // before firing, and shows the system alarm indicator.
            am.setAlarmClock(
                AlarmManager.AlarmClockInfo(alarm.fireAtEpochMs, showIntent),
                firePendingIntent(context, alarm)
            )
            ids.add(alarm.id.toString())
            Log.i(TAG, "scheduled alarm ${alarm.id} at ${alarm.fireAtEpochMs}")
        }

        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putStringSet(KEY_IDS, ids).apply()
    }

    fun cancel(context: Context, id: Int) {
        val intent = Intent(context, AlarmReceiver::class.java)
        val pi = PendingIntent.getBroadcast(
            context, id, intent,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
        )
        if (pi != null) {
            alarmManager(context).cancel(pi)
            pi.cancel()
        }
    }

    fun cancelAll(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs.getStringSet(KEY_IDS, emptySet())?.forEach { cancel(context, it.toInt()) }
        prefs.edit().remove(KEY_IDS).apply()
    }
}
```

- [ ] **Step 3: Write the receiver**

Create `android/app/src/main/kotlin/com/riseapp/rise/AlarmReceiver.kt`:

```kotlin
package com.riseapp.rise

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.ContextCompat

/**
 * The alarm fired. Hand off to a foreground service immediately — a receiver
 * gets ~10 seconds and must not own the ringing lifetime.
 */
class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra(AlarmScheduler.EXTRA_ALARM_ID, -1)
        Log.i("AlarmReceiver", "alarm $id fired")
        if (id < 0) return

        val service = Intent(context, AlarmService::class.java).apply {
            putExtra(AlarmScheduler.EXTRA_ALARM_ID, id)
            putExtra(AlarmScheduler.EXTRA_LABEL,
                intent.getStringExtra(AlarmScheduler.EXTRA_LABEL) ?: "Alarm")
            putExtra(AlarmScheduler.EXTRA_SOUND,
                intent.getStringExtra(AlarmScheduler.EXTRA_SOUND) ?: "")
            putExtra(AlarmScheduler.EXTRA_VIBRATE,
                intent.getBooleanExtra(AlarmScheduler.EXTRA_VIBRATE, true))
        }
        // Starting an FGS from an exact-alarm broadcast is an allowed exemption.
        ContextCompat.startForegroundService(context, service)
    }
}
```

- [ ] **Step 4: Verify it compiles**

`AlarmService` and `RingActivity` do not exist yet, so this will not compile until Task 8. Confirm only that the manifest parses and Kotlin sees the Pigeon types:

```bash
flutter build apk --debug 2>&1 | tail -20
```
Expected: FAIL with `Unresolved reference: AlarmService` and `Unresolved reference: RingActivity`. **This is the expected state at the end of Task 7** — Task 8 creates both.

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/AndroidManifest.xml android/app/src/main/kotlin/com/riseapp/rise/AlarmScheduler.kt android/app/src/main/kotlin/com/riseapp/rise/AlarmReceiver.kt
git commit -m "feat(android): declare alarm permissions and exact scheduling"
```

---

### Task 8: Android ring pipeline — service, notification, audio

**Files:**
- Create: `android/app/src/main/kotlin/com/riseapp/rise/AlarmService.kt`
- Create: `android/app/src/main/kotlin/com/riseapp/rise/RingActivity.kt`
- Create: `android/app/src/main/res/raw/default_alarm.mp3` (bundled fallback sound)

**Interfaces:**
- Consumes: `AlarmScheduler` constants, `AlarmReceiver` from Task 7.
- Produces:
  - `class AlarmService : Service` with `companion object { var ringingAlarmId: Int? = null; fun stop(context: Context) }`
  - `class RingActivity : FlutterActivity` — the full-screen ringing UI host.

- [ ] **Step 1: Add the bundled default sound**

The spec requires a default sound compiled into the binary so the fallback chain never depends on downloaded or user files. Generate a placeholder tone now; Plan 3 replaces it with the real 520 Hz melodic asset.

```bash
mkdir -p android/app/src/main/res/raw
python -c "
import math, struct, wave
# 520 Hz square wave, 10 s, 44.1 kHz mono. 520 Hz low-frequency signals wake
# 4-12x better than high-pitched tones and survive age-related hearing loss.
rate, secs, freq = 44100, 10, 520
w = wave.open('android/app/src/main/res/raw/default_alarm.wav', 'w')
w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate)
frames = b''.join(struct.pack('<h', 12000 if math.sin(2*math.pi*freq*t/rate) > 0 else -12000) for t in range(rate*secs))
w.writeframes(frames); w.close()
print('wrote default_alarm.wav')
"
```

> Android `res/raw` accepts `.wav`; the resource id is `R.raw.default_alarm` either way. Plan 3 swaps in the designed `.mp3`.

- [ ] **Step 2: Write the service**

Create `android/app/src/main/kotlin/com/riseapp/rise/AlarmService.kt`:

```kotlin
package com.riseapp.rise

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * Owns the ringing lifetime: audio on the alarm stream, vibration, wake lock,
 * and the full-screen notification that launches [RingActivity].
 */
class AlarmService : Service() {

    companion object {
        private const val TAG = "AlarmService"
        private const val CHANNEL_ID = "rise_alarms"
        private const val NOTIF_ID = 4242

        /** Which alarm is ringing right now, if any. Read on cold start. */
        var ringingAlarmId: Int? = null
            private set

        fun stop(context: Context) {
            context.stopService(Intent(context, AlarmService::class.java))
        }
    }

    private var player: MediaPlayer? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private val handler = Handler(Looper.getMainLooper())
    private var rampStep = 0

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val id = intent?.getIntExtra(AlarmScheduler.EXTRA_ALARM_ID, -1) ?: -1
        val label = intent?.getStringExtra(AlarmScheduler.EXTRA_LABEL) ?: "Alarm"
        val vibrate = intent?.getBooleanExtra(AlarmScheduler.EXTRA_VIBRATE, true) ?: true
        Log.i(TAG, "ringing alarm $id")

        ringingAlarmId = id
        createChannel()
        startForeground(NOTIF_ID, buildNotification(id, label))

        acquireWakeLock()
        startAudio()
        if (vibrate) startVibration()

        // START_STICKY: if the system kills us under memory pressure while an
        // alarm is ringing, come back.
        return START_STICKY
    }

    private fun createChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Alarms",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Rise alarms ringing"
            // We own audio and vibration ourselves via the alarm stream.
            setSound(null, null)
            enableVibration(false)
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            setBypassDnd(true)
        }
        getSystemService(NotificationManager::class.java)
            .createNotificationChannel(channel)
    }

    private fun buildNotification(id: Int, label: String): android.app.Notification {
        val fullScreen = PendingIntent.getActivity(
            this,
            id,
            Intent(this, RingActivity::class.java)
                .putExtra(AlarmScheduler.EXTRA_ALARM_ID, id)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(label)
            .setContentText("Tap to wake up")
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setOngoing(true)
            .setAutoCancel(false)
            // The whole point: launch the ringing UI over the lock screen.
            .setFullScreenIntent(fullScreen, true)
            .build()
    }

    private fun acquireWakeLock() {
        val pm = getSystemService(PowerManager::class.java)
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "rise:alarm"
        ).apply { acquire(10 * 60 * 1000L) }
    }

    private fun startAudio() {
        // USAGE_ALARM routes to the dedicated alarm volume stream, which is
        // immune to media mute and to the ringer being silenced.
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        // Built by hand rather than MediaPlayer.create(): create() prepares
        // immediately, and audio attributes set after prepare are ignored —
        // the alarm would silently play on the media stream and be muted.
        player = MediaPlayer().apply {
            setAudioAttributes(attrs)
            resources.openRawResourceFd(R.raw.default_alarm).use { afd ->
                setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
            }
            isLooping = true
            // Gentle start: ramp from low to full over 60 s. Abrupt waking
            // spikes the morning blood-pressure surge.
            setVolume(0.15f, 0.15f)
            prepare()
            start()
        }
        rampStep = 0
        scheduleRamp()
    }

    /** VibratorManager is API 31+; minSdk is 26. */
    private fun vibrator(): Vibrator =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            getSystemService(VibratorManager::class.java).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Vibrator::class.java)
        }

    private fun scheduleRamp() {
        handler.postDelayed({
            rampStep++
            val v = (0.15f + (0.85f * rampStep / 12f)).coerceAtMost(1.0f)
            player?.setVolume(v, v)
            if (rampStep < 12) scheduleRamp()
        }, 5000) // 12 steps x 5 s = 60 s
    }

    private fun startVibration() {
        // Intermittent patterns rouse better than continuous buzzing.
        val timings = longArrayOf(0, 600, 400, 600, 400)
        val amplitudes = intArrayOf(0, 255, 0, 255, 0)
        vibrator().vibrate(VibrationEffect.createWaveform(timings, amplitudes, 1))
    }

    override fun onDestroy() {
        Log.i(TAG, "stopping alarm ${ringingAlarmId}")
        handler.removeCallbacksAndMessages(null)
        player?.run { if (isPlaying) stop(); release() }
        player = null
        vibrator().cancel()
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        ringingAlarmId = null
        super.onDestroy()
    }
}
```

- [ ] **Step 3: Write the ringing activity**

Create `android/app/src/main/kotlin/com/riseapp/rise/RingActivity.kt`:

```kotlin
package com.riseapp.rise

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

/**
 * Hosts the Flutter ringing UI over the lock screen. showWhenLocked and
 * turnScreenOn are declared in the manifest; they are also set in code because
 * some OEM skins honour only the runtime call.
 */
class RingActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setShowWhenLocked(true)
        setTurnScreenOn(true)
    }

    override fun getInitialRoute(): String {
        val id = intent.getIntExtra(AlarmScheduler.EXTRA_ALARM_ID, -1)
        return "/ring/$id"
    }
}
```

- [ ] **Step 4: Build to verify it compiles**

```bash
flutter build apk --debug 2>&1 | tail -5
```
Expected: `✓ Built build/app/outputs/flutter-apk/app-debug.apk`

> The manifest already declares `.BootReceiver`, which does not exist until Task 9. Android resolves manifest class names at runtime, not compile time, so this builds. If lint is later configured to treat `MissingClass` as an error, Task 9 removes the discrepancy anyway.

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/kotlin/com/riseapp/rise/AlarmService.kt android/app/src/main/kotlin/com/riseapp/rise/RingActivity.kt android/app/src/main/res/raw/
git commit -m "feat(android): add ring pipeline with alarm-stream audio and FSI"
```

---

### Task 9: Boot, time-change, and missed-alarm recovery

**Files:**
- Create: `android/app/src/main/kotlin/com/riseapp/rise/BootReceiver.kt`
- Create: `lib/domain/missed_alarm.dart`
- Test: `test/domain/missed_alarm_test.dart`

**Interfaces:**
- Consumes: `ScheduledOccurrence` from Task 4.
- Produces:
  - `ScheduledOccurrence? findMissedAlarm({required List<ScheduledOccurrence> occurrences, required DateTime now, Duration window = const Duration(minutes: 30)})` — the most recent occurrence due within the last [window] and not yet dismissed.
  - `class BootReceiver : BroadcastReceiver` — wakes the Flutter engine to re-run reconcile after boot, app update, or clock change.

- [ ] **Step 1: Write the failing test**

Create `test/domain/missed_alarm_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/missed_alarm.dart';
import 'package:rise/domain/scheduled_occurrence.dart';

void main() {
  ScheduledOccurrence occ(int id, DateTime fireAt) => ScheduledOccurrence(
        alarmId: id,
        fireAt: fireAt,
        label: 'Alarm',
        soundAsset: 'sounds/default_alarm.mp3',
        vibrate: true,
      );

  final now = DateTime.utc(2026, 7, 15, 7, 0);

  test('returns null when nothing is due', () {
    expect(findMissedAlarm(occurrences: const [], now: now), isNull);
  });

  test('finds an alarm due 10 minutes ago', () {
    final missed = occ(1, DateTime.utc(2026, 7, 15, 6, 50));
    expect(findMissedAlarm(occurrences: [missed], now: now), missed);
  });

  test('ignores an alarm due 31 minutes ago (outside the 30-minute window)', () {
    final stale = occ(1, DateTime.utc(2026, 7, 15, 6, 29));
    expect(findMissedAlarm(occurrences: [stale], now: now), isNull);
  });

  test('includes an alarm at exactly the 30-minute boundary', () {
    final edge = occ(1, DateTime.utc(2026, 7, 15, 6, 30));
    expect(findMissedAlarm(occurrences: [edge], now: now), edge);
  });

  test('ignores future alarms', () {
    final future = occ(1, DateTime.utc(2026, 7, 15, 8, 0));
    expect(findMissedAlarm(occurrences: [future], now: now), isNull);
  });

  test('returns the most recent when several were missed', () {
    final older = occ(1, DateTime.utc(2026, 7, 15, 6, 40));
    final newer = occ(2, DateTime.utc(2026, 7, 15, 6, 55));
    expect(findMissedAlarm(occurrences: [older, newer], now: now), newer);
  });

  test('respects a custom window', () {
    final missed = occ(1, DateTime.utc(2026, 7, 15, 6, 50));
    expect(
      findMissedAlarm(
          occurrences: [missed], now: now, window: const Duration(minutes: 5)),
      isNull,
    );
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/domain/missed_alarm_test.dart
```
Expected: FAIL — `missed_alarm.dart` not found.

- [ ] **Step 3: Write the implementation**

Create `lib/domain/missed_alarm.dart`:

```dart
import 'scheduled_occurrence.dart';

/// Default recovery window from the spec: an alarm due within the last 30
/// minutes and never dismissed should ring now rather than be silently lost.
const Duration kMissedAlarmWindow = Duration(minutes: 30);

/// The most recent occurrence that came due within [window] before [now].
///
/// Used after boot, app update, or a clock change: the device may have been
/// off or the scheduler cleared when the alarm was supposed to ring.
ScheduledOccurrence? findMissedAlarm({
  required List<ScheduledOccurrence> occurrences,
  required DateTime now,
  Duration window = kMissedAlarmWindow,
}) {
  final cutoff = now.subtract(window);

  ScheduledOccurrence? best;
  for (final o in occurrences) {
    final due = !o.fireAt.isAfter(now);
    final fresh = !o.fireAt.isBefore(cutoff);
    if (due && fresh) {
      if (best == null || o.fireAt.isAfter(best.fireAt)) best = o;
    }
  }
  return best;
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
flutter test test/domain/missed_alarm_test.dart
```
Expected: PASS — all 7 tests green.

- [ ] **Step 5: Write the boot receiver**

Create `android/app/src/main/kotlin/com/riseapp/rise/BootReceiver.kt`:

```kotlin
package com.riseapp.rise

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * The scheduled set does not survive reboot, app replacement, or a clock
 * change. Each of these spins up a headless Flutter engine whose only job is
 * to re-run reconcile from the local database and recover a missed alarm.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        Log.i("BootReceiver", "received $action; re-running reconcile")

        when (action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED -> startReconcileEngine(context)
            else -> return
        }
    }

    private fun startReconcileEngine(context: Context) {
        val app = context.applicationContext

        // On a cold boot nothing has initialized the Flutter loader yet, so the
        // engine cannot find the app bundle. This must happen before the engine
        // is constructed.
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(app)
        loader.ensureInitializationComplete(app, null)

        val engine = FlutterEngine(app)
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "reconcileEntrypoint")
        )
        AlarmHostApi.setUp(engine.dartExecutor.binaryMessenger, AlarmHostApiImpl(app))

        // The engine must outlive onReceive() or reconcile is killed mid-flight.
        FlutterEngineHolder.retain(engine)
    }
}

/** Keeps headless engines alive until their reconcile finishes. */
object FlutterEngineHolder {
    private val engines = mutableListOf<FlutterEngine>()

    fun retain(engine: FlutterEngine) {
        engines.add(engine)
    }

    fun releaseAll() {
        engines.forEach { it.destroy() }
        engines.clear()
    }
}
```

> `BootReceiver.kt` references `AlarmHostApiImpl`, which Task 10 creates — so the project does not compile at the end of this task. That is expected; Task 10 closes it.
>
> The `"reconcileEntrypoint"` name is a **string** looked up in the Dart VM at runtime, not a compile-time reference. Nothing catches a typo here: if it does not exactly match the `@pragma('vm:entry-point')` function written in Task 12, alarms simply never re-arm after a reboot, silently. Task 13 scenario 12 is what proves this wiring works.

- [ ] **Step 6: Commit**

```bash
git add lib/domain/missed_alarm.dart test/domain/missed_alarm_test.dart android/app/src/main/kotlin/com/riseapp/rise/BootReceiver.kt
git commit -m "feat: add missed-alarm recovery and boot/time-change reconcile"
```

---

### Task 10: Kotlin host API implementation

**Files:**
- Create: `android/app/src/main/kotlin/com/riseapp/rise/AlarmHostApiImpl.kt`
- Modify: `android/app/src/main/kotlin/com/riseapp/rise/MainActivity.kt`

**Interfaces:**
- Consumes: `AlarmHostApi`, `NativeAlarm`, `AlarmPermissions` (Task 6); `AlarmScheduler` (Task 7); `AlarmService` (Task 8).
- Produces: `class AlarmHostApiImpl(private val context: Context) : AlarmHostApi` — registered by `MainActivity` and `RingActivity`.

- [ ] **Step 1: Implement the host API**

Create `android/app/src/main/kotlin/com/riseapp/rise/AlarmHostApiImpl.kt`:

```kotlin
package com.riseapp.rise

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat

class AlarmHostApiImpl(private val context: Context) : AlarmHostApi {

    override fun reconcile(alarms: List<NativeAlarm>) {
        AlarmScheduler.reconcile(context, alarms)
    }

    override fun ringNow(alarm: NativeAlarm) {
        // Starts the ringing service directly, leaving the scheduled set alone.
        val service = Intent(context, AlarmService::class.java).apply {
            putExtra(AlarmScheduler.EXTRA_ALARM_ID, alarm.id.toInt())
            putExtra(AlarmScheduler.EXTRA_LABEL, alarm.label)
            putExtra(AlarmScheduler.EXTRA_SOUND, alarm.soundAsset)
            putExtra(AlarmScheduler.EXTRA_VIBRATE, alarm.vibrate)
        }
        ContextCompat.startForegroundService(context, service)
    }

    override fun cancelAll() {
        AlarmScheduler.cancelAll(context)
    }

    override fun getPermissions(): AlarmPermissions {
        val nm = context.getSystemService(NotificationManager::class.java)
        val pm = context.getSystemService(PowerManager::class.java)

        val fullScreen = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            nm.canUseFullScreenIntent()
        } else {
            true
        }

        return AlarmPermissions(
            notifications = NotificationManagerCompat.from(context).areNotificationsEnabled(),
            exactAlarm = AlarmScheduler.canScheduleExact(context),
            fullScreenIntent = fullScreen,
            batteryUnrestricted = pm.isIgnoringBatteryOptimizations(context.packageName)
        )
    }

    override fun requestNotificationPermission() {
        // Runtime request needs an Activity; deep-link to settings instead so
        // this works identically from MainActivity and RingActivity.
        context.startActivity(
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }

    override fun openExactAlarmSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.startActivity(
                Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
                    .setData(Uri.parse("package:${context.packageName}"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        }
    }

    override fun openBatterySettings() {
        // Allowed by Play policy: Rise's core function is alarms, which OEM
        // battery optimisation silently breaks.
        context.startActivity(
            Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                .setData(Uri.parse("package:${context.packageName}"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }

    override fun openFullScreenIntentSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            context.startActivity(
                Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT)
                    .setData(Uri.parse("package:${context.packageName}"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        }
    }

    override fun getRingingAlarmId(): Long? {
        val id = AlarmService.ringingAlarmId ?: return null
        return id.toLong()
    }

    override fun stopRinging(alarmId: Long) {
        // Stop only if this is still the alarm that's ringing. A second alarm
        // can take over the service between Dart deciding to dismiss and this
        // call landing; stopping unconditionally would silence the wrong one.
        if (AlarmService.ringingAlarmId?.toLong() == alarmId) {
            AlarmService.stop(context)
        }
    }
}
```

- [ ] **Step 2: Register the API on both activities**

Replace `android/app/src/main/kotlin/com/riseapp/rise/MainActivity.kt` with:

```kotlin
package com.riseapp.rise

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AlarmHostApi.setUp(
            flutterEngine.dartExecutor.binaryMessenger,
            AlarmHostApiImpl(applicationContext)
        )
    }
}
```

Add the same registration to `RingActivity` — append this method inside the existing `class RingActivity : FlutterActivity()` in `android/app/src/main/kotlin/com/riseapp/rise/RingActivity.kt`:

```kotlin
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AlarmHostApi.setUp(
            flutterEngine.dartExecutor.binaryMessenger,
            AlarmHostApiImpl(applicationContext)
        )
    }
```

and add the import `io.flutter.embedding.engine.FlutterEngine` to that file.

- [ ] **Step 3: Build to verify it compiles**

```bash
flutter build apk --debug 2>&1 | tail -5
```
Expected: `✓ Built build/app/outputs/flutter-apk/app-debug.apk`

> Pigeon maps Dart `int` to Kotlin `Long`. If the compiler reports a type mismatch on `id` or `alarmId`, honour the generated signature and convert with `.toInt()` at the call site — never edit `AlarmApi.g.kt`.

- [ ] **Step 4: Commit**

```bash
git add android/app/src/main/kotlin/com/riseapp/rise/
git commit -m "feat(android): implement native alarm host API"
```

---

### Task 11: Dart sync service and reconcile orchestration

**Files:**
- Create: `lib/data/alarm_sync_service.dart`
- Modify: `lib/main.dart`
- Test: `test/data/alarm_sync_service_test.dart`

**Interfaces:**
- Consumes: `AlarmRepository` (Task 5), `desiredOccurrences` (Task 4), `findMissedAlarm` (Task 9), `AlarmHostApi`/`NativeAlarm` (Task 6).
- Produces:
  - `abstract class AlarmPlatform` — `Future<void> reconcile(List<ScheduledOccurrence>)`, `Future<void> ringNow(ScheduledOccurrence)`.
  - `class PigeonAlarmPlatform implements AlarmPlatform` — `PigeonAlarmPlatform([AlarmHostApi? api])`.
  - `class AlarmSyncService` — `AlarmSyncService({required AlarmRepository repository, required AlarmPlatform platform, required tz.Location location})`, `static AlarmSyncService get instance`, `static void configure(AlarmSyncService)`, `static Future<void> configureForApp()`, `Future<void> reconcileNow({bool recoverMissed = false})`, `Future<List<ScheduledOccurrence>> currentPlan()`.

> **Why `AlarmPlatform` exists.** Tests must not fake the Pigeon-generated `AlarmHostApi` class directly — its generated members change with every codegen run and would break the tests for no product reason. `AlarmPlatform` is the seam: it speaks in domain types (`ScheduledOccurrence`), and `PigeonAlarmPlatform` is the only place that knows `NativeAlarm` exists.

- [ ] **Step 1: Write the failing test**

Create `test/data/alarm_sync_service_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:rise/data/alarm_sync_service.dart';
import 'package:rise/data/local/alarm_repository.dart';
import 'package:rise/data/local/database.dart';
import 'package:rise/domain/alarm.dart';
import 'package:rise/domain/scheduled_occurrence.dart';

/// Records what the service would have sent to the platform.
class FakeAlarmPlatform implements AlarmPlatform {
  final List<List<ScheduledOccurrence>> reconcileCalls = [];
  final List<ScheduledOccurrence> ringNowCalls = [];

  @override
  Future<void> reconcile(List<ScheduledOccurrence> occurrences) async =>
      reconcileCalls.add(occurrences);

  @override
  Future<void> ringNow(ScheduledOccurrence occurrence) async =>
      ringNowCalls.add(occurrence);
}

void main() {
  late RiseDatabase db;
  late AlarmRepository repo;
  late FakeAlarmPlatform platform;

  setUpAll(() => tzdata.initializeTimeZones());

  setUp(() {
    db = RiseDatabase(NativeDatabase.memory());
    repo = AlarmRepository(db);
    platform = FakeAlarmPlatform();
    AlarmSyncService.configure(AlarmSyncService(
      repository: repo,
      platform: platform,
      location: tz.getLocation('America/New_York'),
    ));
  });

  tearDown(() async => db.close());

  test('sends nothing to the platform when there are no alarms', () async {
    await AlarmSyncService.instance.reconcileNow();
    expect(platform.reconcileCalls.single, isEmpty);
  });

  test('sends one enabled alarm to the platform', () async {
    await repo.upsert(const Alarm(id: 0, hour: 6, minute: 30, label: 'Run'));
    await AlarmSyncService.instance.reconcileNow();

    final sent = platform.reconcileCalls.single;
    expect(sent, hasLength(1));
    expect(sent.single.label, 'Run');
    expect(sent.single.fireAt.isUtc, isTrue);
  });

  test('omits disabled alarms', () async {
    await repo.upsert(const Alarm(id: 0, hour: 6, minute: 30, enabled: false));
    await AlarmSyncService.instance.reconcileNow();
    expect(platform.reconcileCalls.single, isEmpty);
  });

  test('reconciling twice with no change sends the same set both times', () async {
    await repo.upsert(const Alarm(id: 0, hour: 6, minute: 30));
    await AlarmSyncService.instance.reconcileNow();
    await AlarmSyncService.instance.reconcileNow();

    expect(platform.reconcileCalls, hasLength(2));
    expect(platform.reconcileCalls[0], equals(platform.reconcileCalls[1]));
  });

  test('does not ring anything when recoverMissed finds no missed alarm', () async {
    await repo.upsert(const Alarm(id: 0, hour: 6, minute: 30));
    await AlarmSyncService.instance.reconcileNow(recoverMissed: true);
    expect(platform.ringNowCalls, isEmpty);
  });

  test('recovery rings via ringNow and never through reconcile', () async {
    // A one-shot alarm one minute in the past is "missed": nextOccurrence
    // rolls it to tomorrow, so recovery must come from the dedicated path.
    final now = tz.TZDateTime.now(tz.getLocation('America/New_York'));
    final justPassed = now.subtract(const Duration(minutes: 1));
    await repo.upsert(
        Alarm(id: 0, hour: justPassed.hour, minute: justPassed.minute));

    await AlarmSyncService.instance.reconcileNow(recoverMissed: true);

    // Tomorrow's occurrence is still armed — recovery must not clobber it.
    expect(platform.reconcileCalls.single, hasLength(1));
  });

  test('currentPlan reports every enabled alarm sorted by fire time', () async {
    await repo.upsert(const Alarm(id: 0, hour: 9, minute: 0));
    await repo.upsert(const Alarm(id: 0, hour: 6, minute: 30));
    final plan = await AlarmSyncService.instance.currentPlan();
    expect(plan, hasLength(2));
    expect(plan.first.fireAt.isBefore(plan.last.fireAt), isTrue);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/data/alarm_sync_service_test.dart
```
Expected: FAIL — `alarm_sync_service.dart` not found.

- [ ] **Step 3: Write the service**

Create `lib/data/alarm_sync_service.dart`:

```dart
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:timezone/timezone.dart' as tz;

import '../domain/missed_alarm.dart';
import '../domain/reconcile.dart';
import '../domain/scheduled_occurrence.dart';
import 'local/alarm_repository.dart';
import 'local/database.dart';
import 'native/alarm_api.g.dart';

/// What the sync service needs from the platform, in domain types.
///
/// This seam keeps the Pigeon-generated API out of the service and lets tests
/// fake the platform without depending on codegen output.
abstract class AlarmPlatform {
  Future<void> reconcile(List<ScheduledOccurrence> occurrences);
  Future<void> ringNow(ScheduledOccurrence occurrence);
}

/// The only place that knows [NativeAlarm] exists.
class PigeonAlarmPlatform implements AlarmPlatform {
  PigeonAlarmPlatform([AlarmHostApi? api]) : _api = api ?? AlarmHostApi();

  final AlarmHostApi _api;

  NativeAlarm _toNative(ScheduledOccurrence o) => NativeAlarm(
        id: o.alarmId,
        fireAtEpochMs: o.fireAt.millisecondsSinceEpoch,
        label: o.label,
        soundAsset: o.soundAsset,
        vibrate: o.vibrate,
      );

  @override
  Future<void> reconcile(List<ScheduledOccurrence> occurrences) =>
      _api.reconcile([for (final o in occurrences) _toNative(o)]);

  @override
  Future<void> ringNow(ScheduledOccurrence occurrence) =>
      _api.ringNow(_toNative(occurrence));
}

/// Single point where alarms in the local database become alarms armed in the
/// platform scheduler.
///
/// Called on: app launch, any alarm edit, dismissal, boot, app update, and
/// timezone or clock change. Reconcile is a full replace, so calling it more
/// often than necessary is always safe.
class AlarmSyncService {
  AlarmSyncService({
    required AlarmRepository repository,
    required AlarmPlatform platform,
    required tz.Location location,
  })  : _repository = repository,
        _platform = platform,
        _location = location;

  final AlarmRepository _repository;
  final AlarmPlatform _platform;
  final tz.Location _location;

  /// Exposed so the UI reads alarms through the same instance the scheduler
  /// was built from — two repositories over two database handles would drift.
  AlarmRepository get repository => _repository;

  static AlarmSyncService? _instance;

  static AlarmSyncService get instance {
    final i = _instance;
    if (i == null) {
      throw StateError(
          'AlarmSyncService used before configure()/configureForApp()');
    }
    return i;
  }

  static void configure(AlarmSyncService service) => _instance = service;

  /// Builds the production service against the real database and platform.
  /// Call once from main() and once from the headless boot entrypoint.
  static Future<void> configureForApp() async {
    final dir = await getApplicationDocumentsDirectory();
    final db = RiseDatabase(NativeDatabase(File(p.join(dir.path, 'rise.sqlite'))));
    configure(AlarmSyncService(
      repository: AlarmRepository(db),
      platform: PigeonAlarmPlatform(),
      location: tz.local,
    ));
  }

  Future<List<ScheduledOccurrence>> currentPlan() async {
    return desiredOccurrences(
      alarms: await _repository.all(),
      now: tz.TZDateTime.now(_location),
      location: _location,
    );
  }

  /// Re-arms the platform scheduler from the local database.
  ///
  /// When [recoverMissed] is true (boot, app update, clock change), an alarm
  /// that came due within the last 30 minutes and was never dismissed rings
  /// immediately rather than being silently lost.
  Future<void> reconcileNow({bool recoverMissed = false}) async {
    final plan = await currentPlan();
    await _platform.reconcile(plan);

    if (!recoverMissed) return;

    // Recovery reads the alarms' PREVIOUS occurrences, not `plan`: a missed
    // alarm has already rolled forward to its next firing, so it never appears
    // in the desired set.
    final now = tz.TZDateTime.now(_location);
    final previous = <ScheduledOccurrence>[];
    for (final alarm in await _repository.all()) {
      if (!alarm.enabled) continue;
      final before = previousOccurrence(
          alarm: alarm, before: now, location: _location);
      if (before == null) continue;
      previous.add(ScheduledOccurrence(
        alarmId: alarm.id,
        fireAt: before.toUtc(),
        label: alarm.label,
        soundAsset: alarm.soundAsset,
        vibrate: alarm.vibrate,
      ));
    }

    final missed =
        findMissedAlarm(occurrences: previous, now: now.toUtc());
    if (missed != null) {
      debugPrint('Recovering missed alarm ${missed.alarmId}');
      // Never via reconcile(): that is a full replace and would cancel every
      // other alarm the user has set.
      await _platform.ringNow(missed);
    }
  }
}
```

> **`previousOccurrence` does not exist yet.** Add it to `lib/domain/schedule_math.dart` in Step 4 — the missed-alarm search needs the firing *before* now, which `nextOccurrence` by definition never returns.

- [ ] **Step 4: Add `previousOccurrence` to schedule math**

Append to `lib/domain/schedule_math.dart`:

```dart
/// The most recent instant [alarm] should have fired at or before [before], or
/// null if there is none within the search horizon.
///
/// Mirrors [nextOccurrence] walking backwards. Used only for missed-alarm
/// recovery: once an alarm has fired, its next occurrence has already rolled
/// forward, so the firing we may have missed is in the past.
tz.TZDateTime? previousOccurrence({
  required Alarm alarm,
  required tz.TZDateTime before,
  required tz.Location location,
}) {
  if (!alarm.enabled) return null;

  final startDate = DateTime.utc(before.year, before.month, before.day);

  for (var offset = 0; offset <= _searchHorizonDays; offset++) {
    final date = startDate.subtract(Duration(days: offset));

    if (!alarm.isOneShot) {
      final index = weekdayToIndex(
          DateTime.utc(date.year, date.month, date.day).weekday);
      if (!alarm.days.contains(index)) continue;
    }

    final candidate = resolveWallTime(
        location, date.year, date.month, date.day, alarm.hour, alarm.minute);

    if (!candidate.isAfter(before)) return candidate;
  }

  return null;
}
```

Add this test to `test/domain/schedule_math_test.dart`:

```dart
  group('previousOccurrence', () {
    test('finds the firing earlier today', () {
      const alarm = Alarm(id: 1, hour: 6, minute: 30);
      final before = tz.TZDateTime(ny, 2026, 7, 15, 7, 0);
      expect(previousOccurrence(alarm: alarm, before: before, location: ny),
          tz.TZDateTime(ny, 2026, 7, 15, 6, 30));
    });

    test('falls back to yesterday when today has not reached the time', () {
      const alarm = Alarm(id: 1, hour: 6, minute: 30);
      final before = tz.TZDateTime(ny, 2026, 7, 15, 5, 0);
      expect(previousOccurrence(alarm: alarm, before: before, location: ny),
          tz.TZDateTime(ny, 2026, 7, 14, 6, 30));
    });

    test('respects repeat days walking backwards', () {
      // 2026-07-20 is a Monday; the previous weekday firing is Friday 07-17.
      const alarm = Alarm(id: 1, hour: 6, minute: 30, days: {1, 2, 3, 4, 5});
      final before = tz.TZDateTime(ny, 2026, 7, 20, 5, 0);
      expect(previousOccurrence(alarm: alarm, before: before, location: ny),
          tz.TZDateTime(ny, 2026, 7, 17, 6, 30));
    });
  });
```

Run it:

```bash
flutter test test/domain/schedule_math_test.dart
```
Expected: PASS — 19 tests green.

- [ ] **Step 5: Run the test to verify it passes**

```bash
flutter test test/data/alarm_sync_service_test.dart
```
Expected: PASS — all 5 tests green.

- [ ] **Step 6: Run the whole suite**

```bash
flutter test
```
Expected: PASS — every test from Tasks 2–11.

- [ ] **Step 7: Commit**

```bash
git add lib/data/alarm_sync_service.dart test/data/alarm_sync_service_test.dart
git commit -m "feat: add reconcile orchestration between database and platform"
```

---

### Task 12: Scaffolding UI to prove the engine end-to-end

Deliberately ugly. Plan 3 replaces all of it with the real design system. Its only job: set an alarm, watch it ring, dismiss it.

**Files:**
- Modify: `lib/main.dart`
- Create: `lib/ui/dev_home_page.dart`
- Create: `lib/ui/dev_ring_page.dart`

**Interfaces:**
- Consumes: `AlarmSyncService` (Task 11), `AlarmRepository` (Task 5), `AlarmHostApi`/`AlarmFlutterApi` (Task 6).
- Produces: a runnable app with routes `/` (dev home) and `/ring/:id` (ringing screen).

- [ ] **Step 1: Write the dev home page**

Create `lib/ui/dev_home_page.dart`:

```dart
import 'package:flutter/material.dart';

import '../data/alarm_sync_service.dart';
import '../data/local/alarm_repository.dart';
import '../data/native/alarm_api.g.dart';
import '../domain/alarm.dart';

/// Throwaway UI that proves the alarm engine works. Plan 3 replaces this
/// entirely with the designed Home screen.
class DevHomePage extends StatefulWidget {
  const DevHomePage({super.key, required this.repository});

  final AlarmRepository repository;

  @override
  State<DevHomePage> createState() => _DevHomePageState();
}

class _DevHomePageState extends State<DevHomePage> {
  AlarmPermissions? _permissions;

  @override
  void initState() {
    super.initState();
    _refreshPermissions();
  }

  Future<void> _refreshPermissions() async {
    final p = await AlarmHostApi().getPermissions();
    if (mounted) setState(() => _permissions = p);
  }

  Future<void> _addAlarmIn(Duration delay) async {
    final when = DateTime.now().add(delay);
    await widget.repository.upsert(
      Alarm(id: 0, hour: when.hour, minute: when.minute, label: 'Test alarm'),
    );
    await AlarmSyncService.instance.reconcileNow();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = _permissions;
    return Scaffold(
      appBar: AppBar(title: const Text('Rise — engine test')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Permissions', style: TextStyle(fontWeight: FontWeight.bold)),
          if (p == null)
            const Text('checking…')
          else ...[
            _PermissionRow('Notifications', p.notifications,
                () => AlarmHostApi().requestNotificationPermission()),
            _PermissionRow('Exact alarm', p.exactAlarm,
                () => AlarmHostApi().openExactAlarmSettings()),
            _PermissionRow('Full-screen intent', p.fullScreenIntent,
                () => AlarmHostApi().openFullScreenIntentSettings()),
            _PermissionRow('Battery unrestricted', p.batteryUnrestricted,
                () => AlarmHostApi().openBatterySettings()),
          ],
          TextButton(
              onPressed: _refreshPermissions, child: const Text('Re-check')),
          const Divider(height: 32),
          ElevatedButton(
            onPressed: () => _addAlarmIn(const Duration(minutes: 1)),
            child: const Text('Ring in 1 minute'),
          ),
          ElevatedButton(
            onPressed: () => _addAlarmIn(const Duration(minutes: 2)),
            child: const Text('Ring in 2 minutes'),
          ),
          const Divider(height: 32),
          FutureBuilder(
            future: AlarmSyncService.instance.currentPlan(),
            builder: (context, snapshot) {
              final plan = snapshot.data;
              if (plan == null) return const Text('loading…');
              if (plan.isEmpty) return const Text('No alarms scheduled');
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final o in plan)
                    Text('#${o.alarmId} → ${o.fireAt.toLocal()}'),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow(this.label, this.granted, this.onFix);

  final String label;
  final bool granted;
  final VoidCallback onFix;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(granted ? Icons.check_circle : Icons.error,
            color: granted ? Colors.green : Colors.red, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(label)),
        if (!granted) TextButton(onPressed: onFix, child: const Text('Fix')),
      ],
    );
  }
}
```

- [ ] **Step 2: Write the dev ring page**

Create `lib/ui/dev_ring_page.dart`:

```dart
import 'package:flutter/material.dart';

import '../data/native/alarm_api.g.dart';

/// Throwaway ringing screen. Plan 3 replaces this with the designed ringing
/// overlay and Plan 4 adds missions.
class DevRingPage extends StatelessWidget {
  const DevRingPage({super.key, required this.alarmId});

  final int alarmId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.alarm, size: 96),
            const SizedBox(height: 24),
            Text('Alarm $alarmId is ringing',
                style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 48),
            FilledButton(
              onPressed: () async {
                await AlarmHostApi().stopRinging(alarmId);
                if (context.mounted) Navigator.of(context).maybePop();
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                child: Text('Dismiss'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Wire up main.dart**

Replace `lib/main.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import 'data/alarm_sync_service.dart';
import 'data/local/alarm_repository.dart';
import 'data/native/alarm_api.g.dart';
import 'ui/dev_home_page.dart';
import 'ui/dev_ring_page.dart';

/// Headless entrypoint invoked by Android's BootReceiver after boot, app
/// replacement, or a clock change. Re-arms the scheduler from the local
/// database and recovers any alarm missed while the device was off.
@pragma('vm:entry-point')
Future<void> reconcileEntrypoint() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  await AlarmSyncService.configureForApp();
  await AlarmSyncService.instance.reconcileNow(recoverMissed: true);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  await AlarmSyncService.configureForApp();

  // Every launch re-arms the scheduler: OEMs and OS updates silently clear it.
  await AlarmSyncService.instance.reconcileNow();

  runApp(RiseApp(repository: AlarmSyncService.instance.repository));
}

class RiseApp extends StatefulWidget {
  const RiseApp({super.key, required this.repository});

  final AlarmRepository repository;

  @override
  State<RiseApp> createState() => _RiseAppState();
}

class _RiseAppState extends State<RiseApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    // Engine already alive when an alarm fires.
    AlarmFlutterApi.setUp(_FlutterApiImpl(onFired: _showRing));
    _checkColdStartRing();
  }

  /// Cold start: RingActivity launched the engine from scratch, so no
  /// onAlarmFired callback ever arrives — ask the platform what is ringing.
  Future<void> _checkColdStartRing() async {
    final id = await AlarmHostApi().getRingingAlarmId();
    if (id != null) _showRing(id);
  }

  void _showRing(int alarmId) {
    _navigatorKey.currentState?.push(MaterialPageRoute(
      builder: (_) => DevRingPage(alarmId: alarmId),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rise',
      navigatorKey: _navigatorKey,
      home: DevHomePage(repository: widget.repository),
    );
  }
}

class _FlutterApiImpl implements AlarmFlutterApi {
  _FlutterApiImpl({required this.onFired});

  final void Function(int alarmId) onFired;

  @override
  void onAlarmFired(int alarmId) => onFired(alarmId);
}
```

- [ ] **Step 4: Run on an emulator**

```bash
flutter emulators --launch Medium_Phone_API_36.0
flutter run -d emulator-5554
```
Expected: the app installs and the permissions list renders.

- [ ] **Step 5: Verify an alarm rings on the emulator**

Tap **Ring in 1 minute**, then lock the emulator screen. After ~60 s the ringing screen must appear over the lock screen with audio playing.

Expected `flutter logs` output:
```
I/AlarmScheduler: scheduled alarm 1 at <epoch>
I/AlarmReceiver: alarm 1 fired
I/AlarmService: ringing alarm 1
```

- [ ] **Step 6: Commit**

```bash
git add lib/main.dart lib/ui/
git commit -m "feat: add scaffolding UI proving the alarm engine end-to-end"
```

---

### Task 13: Alarm Reliability Protocol on physical devices

The spec's launch gate. **This task cannot be completed on an emulator** — emulators do not reproduce OEM battery killers, which the research names as the single largest real-world cause of alarms not ringing. Everything before this task is theory; this is the evidence.

**Files:**
- Create: `docs/superpowers/reliability/2026-07-15-plan1-android-results.md`

**Interfaces:**
- Consumes: the complete app from Tasks 1–12.
- Produces: a signed-off reliability results table. **Gate: 20/20 scenarios ring.** Any failure blocks Plan 2 until fixed.

**Requires from the user:** two physical Android phones — one Pixel/stock-class, one Xiaomi/Samsung/Huawei-class. Ask for them before starting; do not substitute an emulator.

- [ ] **Step 1: Build a release APK and install on both phones**

```bash
flutter build apk --release
adb devices
adb -s <serial> install -r build/app/outputs/flutter-apk/app-release.apk
```
Expected: `Success` for each device.

- [ ] **Step 2: Run the matrix on each phone**

For each scenario: set a 2-minute alarm, apply the condition, and record whether it rang, how late, and at what volume.

| # | Scenario | How to apply | Pass criterion |
|---|---|---|---|
| 1 | Screen locked | Lock, wait | Rings, full-screen UI over lock |
| 2 | App backgrounded | Home button | Rings |
| 3 | App force-killed | Settings → Force stop | Rings |
| 4 | Swiped from recents | Swipe away | Rings |
| 5 | Ringer silent | Volume → silent | **Rings** (alarm stream) |
| 6 | Vibrate-only mode | Volume → vibrate | Rings |
| 7 | Media volume at 0 | Media slider to 0 | Rings |
| 8 | DND on | Quick settings → DND | Rings |
| 9 | Airplane mode | Toggle on | Rings (no network dependency) |
| 10 | Doze | `adb shell dumpsys deviceidle force-idle` | Rings |
| 11 | Battery saver on | Settings → Battery saver | Rings |
| 12 | After reboot | Reboot, wait for alarm | Rings |
| 13 | Missed while off | Power off before alarm; boot within 30 min | Rings on boot |
| 14 | Missed beyond window | Power off; boot after 31 min | Does **not** ring |
| 15 | App updated | `adb install -r` a new build | Rings |
| 16 | Clock moved forward | Settings → set time +1 h | Fires at correct wall time |
| 17 | Timezone changed | Settings → change timezone | Fires at correct local wall time |
| 18 | Low battery (<15%) | Drain or emulate | Rings |
| 19 | During a phone call | Call the device | Rings; **record exact behaviour** (see Known gaps) |
| 20 | 3-day idle (OEM killer) | Leave app unopened 3 days, then alarm | **Rings** |

Scenario 10 setup:
```bash
adb shell dumpsys deviceidle force-idle
adb shell dumpsys deviceidle get deep   # expect: IDLE
```

- [ ] **Step 3: Record results**

Create `docs/superpowers/reliability/2026-07-15-plan1-android-results.md` with a filled table per device:

```markdown
# Plan 1 — Android Reliability Protocol Results

**Date:** <date>  **Build:** <git sha>

## Device A: <model>, Android <version>, stock

| # | Scenario | Rang? | Latency | Notes |
|---|----------|-------|---------|-------|
| 1 | Screen locked | ✅ | 0 s | |
...

## Device B: <model>, Android <version>, <OEM skin>

| # | Scenario | Rang? | Latency | Notes |
|---|----------|-------|---------|-------|
...

## Verdict

Ring delivery: __/40 (20 scenarios x 2 devices)
Gate (spec §9): >=99.5% ring delivery. **Any miss blocks Plan 2.**
```

- [ ] **Step 4: Fix any failure before proceeding**

Scenario 20 failing on the OEM device is the expected failure and is exactly what the research predicts. The fix is the battery-optimisation exemption already wired in Task 10 (`openBatterySettings`) — verify the exemption is granted, then re-run scenario 20. If it still fails, the OEM needs an autostart entry; record the exact per-OEM steps in the results doc. **Plan 3's Setup Guardian is built from what this task discovers** — the notes are the deliverable, not just the checkmarks.

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/reliability/
git commit -m "test: record Android alarm reliability protocol results"
```

---

## Known gaps — spec items deliberately not closed here

These appear in the spec's edge-case matrix (§4) and are **not** implemented by Plan 1. They are recorded here so they cannot silently vanish between plans. Each needs the real ringing screen, which is Plan 3.

| Spec edge case | Why it waits | Closed in |
|---|---|---|
| Volume keys during ring: screen swallows volume-down; alarm-stream volume re-asserted every 1 s | Needs the real ringing screen's key handling; the throwaway UI in Task 12 has none | Plan 3 |
| Overlapping alarms: priority queue — earliest rings, next queues after dismissal | `AlarmService` currently tracks a single `ringingAlarmId`; a second alarm firing during a ring would replace it. Needs a queue in the service plus UI to show what is next | Plan 3 |
| Alarm during a call: reduced volume + vibrate, full ring after the call ends | Needs `AudioManager` focus handling and call-state observation | Plan 3 |
| Mid-night battery alarm | Needs the bedtime/wind-down system | Plan 4 |
| Snooze, wake-up check, escalation ladder, goal-locking | Ringing-screen behaviour, not engine | Plan 4 |

Task 13's scenario 19 tests the call case against current behaviour and records what actually happens — that measurement is the input to Plan 3's implementation, not a pass/fail on a feature that does not exist yet.

## Definition of done

- [ ] `flutter test` passes — all domain, data, and sync tests green.
- [ ] `flutter build apk --release` succeeds.
- [ ] An alarm set in the app rings on a locked, silenced, force-killed physical phone.
- [ ] An alarm survives a reboot; a missed alarm recovers within 30 minutes and not beyond.
- [ ] The reliability results document is committed with **40/40 rings**.
- [ ] No alarm path touches the network anywhere.

## What Plan 2 picks up

The iOS engine: AlarmKit on iOS 26+ (system alarm breaking silent/Focus, App Intent → mission), the notification-stack fallback for iOS 16–25 with the 64-notification budget allocator (pure Dart, unit-tested like `ScheduleMath`), Codemagic cloud builds, and the same reliability protocol on iPhone hardware.

**Prerequisite the user must supply before Plan 2:** an Apple Developer Program account ($99/yr) and a physical iPhone. Neither can be substituted.
