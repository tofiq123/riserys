# Phase 4a — Wake data, streaks & stats — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record a local wake-event per alarm firing, compute a streak from the event log, and surface it (live Home streak pill + a Stats screen) — the first of two Phase-4 increments.

**Architecture:** A new `wake_events` Drift table (schema v3) is written by a `WakeRecorder` that opens an event when the ring screen appears and finalizes it on dismissal. A pure `computeStreak` function folds the event log into streak stats (no stored mutable counter). Riverpod exposes the events and stats; the Home pill and a new Stats screen render them. No new native code.

**Tech Stack:** Flutter 3.35 / Dart 3.9, Drift SQLite, flutter_riverpod 2.6.1, shadcn "Mono" design system.

## Global Constraints

- `flutter_riverpod` is pinned to **2.6.1** — use the 2.x API only (Provider/StreamProvider/StateNotifierProvider/StateProvider). No 3.x-only API.
- **Local only.** No network/auth/cloud in Phase 4a. Designed so Phase 5 can later sync `wake_events` to Supabase.
- **Drift:** `schemaVersion` → **3**; the migration is idempotent and multi-isolate-safe (foreground/ring/boot isolates can race the first upgrade) — check sqlite's own schema before DDL. `wake_events` is **independent** of `alarms` (no FK/cascade); deleting an alarm keeps its events.
- **All timestamps stored UTC.** Day-grouping for streaks uses the **local** calendar day of `firstRingAt` (device tz is set at startup via flutter_timezone).
- **Streak rules:** on-time grace = **15 minutes** (dismissed within 15 min of `firstRingAt`); a day succeeds with ≥1 on-time event; a past ring with no on-time dismissal is a miss; no-alarm days are neutral (skipped). A **freeze** (earned 1 per 7 consecutive successes, cap 2) absorbs a miss before the streak breaks. The streak is a **pure function** recomputed from the event log every time.
- **Design tokens only:** colours/spacing/radii/text via `RiseColors`/`RiseSpacing`/`RiseRadii`/`RiseText` (`lib/ui/theme/`). No raw literal that duplicates an existing token.
- **Recording must never break the ring:** every wake-event write is best-effort (wrapped so a failure is logged, never thrown into the dismiss path).
- **TDD, teeth-first:** every test must fail if its target behaviour breaks (no tautologies). Use `pump` (never `pumpAndSettle`) around the ring screen's repeating animation.

## File Structure

- `lib/domain/wake_event.dart` — `WakeEvent` immutable entity (Task 1).
- `lib/domain/streak.dart` — `DayOutcome`, `StreakStats`, `computeStreak` pure function (Task 2).
- `lib/data/local/database.dart` — MODIFY: `WakeEvents` table + schema v3 migration + `_tableExists` (Task 3).
- `lib/data/local/wake_event_repository.dart` — `WakeEventRepository` (Task 4).
- `lib/data/wake_recorder.dart` — `WakeRecorder` service (Task 5).
- `lib/data/alarm_sync_service.dart` — MODIFY: expose the `RiseDatabase` (Task 5).
- `lib/ui/state/wake_providers.dart` — repo/recorder/events/streak providers (Task 5).
- `lib/ui/screens/ring_screen.dart` — MODIFY: open on mount, finalize on dismiss, pass dismiss `method` (Task 6).
- `lib/main.dart` — MODIFY: the real ring records (`record: true`) (Task 6).
- `lib/ui/screens/home_screen.dart` — MODIFY: live streak pill + `onStreak` (Task 7).
- `lib/ui/screens/stats_screen.dart` — `StatsScreen` (Task 8).
- `lib/ui/screens/app_shell.dart` — MODIFY: Sleep→Stats tab + `onStreak` deep-link (Task 9).

---

### Task 1: WakeEvent entity

**Files:**
- Create: `lib/domain/wake_event.dart`
- Test: `test/domain/wake_event_test.dart`

**Interfaces:**
- Produces: `class WakeEvent` — `WakeEvent({required int id, required int alarmId, required DateTime scheduledAt, required DateTime firstRingAt, DateTime? dismissedAt, String? method, int snoozeCount = 0, int missionFailures = 0, bool onTime = false, String label = 'Alarm'})`. Getters: `bool get isOpen` (`dismissedAt == null`), `Duration? get timeToWake` (`dismissedAt − scheduledAt`, or null), `DateTime get localDay` (local midnight of `firstRingAt`). Plus `copyWith`, `==`/`hashCode` (instant-normalised for the DateTimes), `toString`.

- [ ] **Step 1: Write the failing test**

Create `test/domain/wake_event_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/wake_event.dart';

void main() {
  final ring = DateTime.utc(2026, 7, 17, 6, 0);

  test('isOpen is true until dismissed', () {
    final e = WakeEvent(id: 1, alarmId: 2, scheduledAt: ring, firstRingAt: ring);
    expect(e.isOpen, isTrue);
    expect(e.copyWith(dismissedAt: ring.add(const Duration(minutes: 3))).isOpen, isFalse);
  });

  test('timeToWake is dismissedAt minus scheduledAt, or null when open', () {
    final e = WakeEvent(id: 1, alarmId: 2, scheduledAt: ring, firstRingAt: ring);
    expect(e.timeToWake, isNull);
    final done = e.copyWith(dismissedAt: ring.add(const Duration(minutes: 4)));
    expect(done.timeToWake, const Duration(minutes: 4));
  });

  test('localDay is the local-midnight of firstRingAt', () {
    final e = WakeEvent(id: 1, alarmId: 2, scheduledAt: ring, firstRingAt: ring);
    final l = ring.toLocal();
    expect(e.localDay, DateTime(l.year, l.month, l.day));
    expect(e.localDay.hour, 0);
  });

  test('equality treats the same instant across UTC/local as equal', () {
    final a = WakeEvent(id: 1, alarmId: 2, scheduledAt: ring, firstRingAt: ring,
        dismissedAt: ring.add(const Duration(minutes: 3)));
    final b = a.copyWith(dismissedAt: ring.add(const Duration(minutes: 3)).toLocal());
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
flutter test test/domain/wake_event_test.dart
```
Expected: FAIL — `wake_event.dart` not found.

- [ ] **Step 3: Write the entity**

Create `lib/domain/wake_event.dart`:

```dart
/// One logical firing of an alarm: opened when the ring starts, finalised on
/// dismissal. [dismissedAt] == null means still open — and, once the day is
/// past, a miss. All DateTimes are stored UTC; [localDay] does the only
/// local-time reasoning (streak day-grouping).
class WakeEvent {
  const WakeEvent({
    required this.id,
    required this.alarmId,
    required this.scheduledAt,
    required this.firstRingAt,
    this.dismissedAt,
    this.method,
    this.snoozeCount = 0,
    this.missionFailures = 0,
    this.onTime = false,
    this.label = 'Alarm',
  });

  final int id;
  final int alarmId;
  final DateTime scheduledAt;
  final DateTime firstRingAt;
  final DateTime? dismissedAt;

  /// 'mission' | 'slide' | 'safety' | null.
  final String method;
  // (nullable) — declared below via the `?`.

  final int snoozeCount;
  final int missionFailures;
  final bool onTime;
  final String label;

  bool get isOpen => dismissedAt == null;

  Duration? get timeToWake => dismissedAt?.difference(scheduledAt);

  DateTime get localDay {
    final l = firstRingAt.toLocal();
    return DateTime(l.year, l.month, l.day);
  }

  WakeEvent copyWith({
    int? id,
    int? alarmId,
    DateTime? scheduledAt,
    DateTime? firstRingAt,
    DateTime? dismissedAt,
    String? method,
    int? snoozeCount,
    int? missionFailures,
    bool? onTime,
    String? label,
  }) {
    return WakeEvent(
      id: id ?? this.id,
      alarmId: alarmId ?? this.alarmId,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      firstRingAt: firstRingAt ?? this.firstRingAt,
      dismissedAt: dismissedAt ?? this.dismissedAt,
      method: method ?? this.method,
      snoozeCount: snoozeCount ?? this.snoozeCount,
      missionFailures: missionFailures ?? this.missionFailures,
      onTime: onTime ?? this.onTime,
      label: label ?? this.label,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WakeEvent &&
      other.id == id &&
      other.alarmId == alarmId &&
      other.scheduledAt.isAtSameMomentAs(scheduledAt) &&
      other.firstRingAt.isAtSameMomentAs(firstRingAt) &&
      _sameInstant(other.dismissedAt, dismissedAt) &&
      other.method == method &&
      other.snoozeCount == snoozeCount &&
      other.missionFailures == missionFailures &&
      other.onTime == onTime &&
      other.label == label;

  @override
  int get hashCode => Object.hash(id, alarmId, scheduledAt.toUtc(),
      firstRingAt.toUtc(), dismissedAt?.toUtc(), method, snoozeCount,
      missionFailures, onTime, label);

  @override
  String toString() =>
      'WakeEvent(id: $id, alarm: $alarmId, ring: ${firstRingAt.toIso8601String()}, '
      'dismissed: $dismissedAt, onTime: $onTime, snoozes: $snoozeCount)';
}

bool _sameInstant(DateTime? a, DateTime? b) {
  if (a == null || b == null) return a == null && b == null;
  return a.isAtSameMomentAs(b);
}
```

> **Implementer note:** `method` is nullable — declare it `final String? method;` (the doc comment above sits over it). Everything else is as written.

- [ ] **Step 4: Run it to verify it passes**

```bash
flutter test test/domain/wake_event_test.dart
```
Expected: PASS — 4 tests green.

- [ ] **Step 5: Run analyze and commit**

```bash
flutter analyze
git add lib/domain/wake_event.dart test/domain/wake_event_test.dart
git commit -m "feat(domain): add WakeEvent entity"
```

---

## Remaining tasks (Tasks 2–9 — full code written just before each is executed)

Tasks 2–9 build on Task 1 and each other; each gets its complete code just before dispatch (same flow used for Plan 3). Summary + interfaces:

- **Task 2 — Streak engine** (`lib/domain/streak.dart`): `enum DayOutcome { success, miss, neutral, pending }`; `class StreakStats { int current; int best; int freezesRemaining; Map<DateTime,DayOutcome> byDay; }`; `StreakStats computeStreak(List<WakeEvent> events, DateTime now, {int freezeCap = 2, int earnEvery = 7})`. Pure; heavy unit tests (clean run, miss breaks, freeze absorbs, earn-at-7/cap-2, neutral skipped, today success vs pending, empty).
- **Task 3 — WakeEvents table** (modify `database.dart`): `@DataClassName('WakeEventRow')` table `WakeEvents` mirroring the entity columns; `schemaVersion` 3; idempotent `from < 3` migration guarded by a new `_tableExists(name)` helper; register in `@DriftDatabase(tables: [Alarms, WakeEvents])`. Migration-idempotency test.
- **Task 4 — WakeEventRepository** (`wake_event_repository.dart`): `openRing({alarmId, scheduledAt, firstRingAt, label}) → Future<int>` (reuse an open event for the alarm within 6 h, else insert); `finalizeDismiss({alarmId, dismissedAt, method}) → Future<void>` (find open event, set `dismissedAt`/`method`/`onTime = dismissedAt−firstRingAt ≤ 15 min`; no-op if none); `watchAll() → Stream<List<WakeEvent>>`. Tests: reuse-window, onTime boundary 14:59/15:01, no-op on closed/missing.
- **Task 5 — WakeRecorder + providers** (`wake_recorder.dart`, `wake_providers.dart`; expose `RiseDatabase` on `AlarmSyncService`): `WakeRecorder(repo, alarmRepo)` with `openRing(int alarmId)` (looks up the alarm → label + `scheduledAt` = today's local h:m→UTC) and `finalizeDismiss(int alarmId, {String? method})`; providers `wakeEventRepositoryProvider`, `wakeRecorderProvider`, `wakeEventsProvider`, `streakProvider = computeStreak(events, DateTime.now())`.
- **Task 6 — Wire recording into the ring flow** (modify `ring_screen.dart` + `main.dart`): add `bool record = false`; when `record`, `initState` opens (`ref.read(wakeRecorderProvider).openRing`) and a successful `_dismiss(method)` finalizes — both wrapped best-effort; `_dismiss` takes the method ('mission' vs 'slide'); `main._showRing` passes `record: true`. Existing ring tests keep passing (default `record: false` → no provider read); a new test with a fake recorder verifies open+finalize.
- **Task 7 — Live Home streak pill** (modify `home_screen.dart`): add `onStreak` callback; the header renders a tappable flame+count pill from `streakProvider` (muted "Start a streak" at 0). Tests: pill shows count; tap calls `onStreak`.
- **Task 8 — Stats screen** (`stats_screen.dart`): consumes `streakProvider` + `wakeEventsProvider`; current/best streak, freezes, on-time calendar (~30-day grid), 7-day wake-vs-set chart (+ snooze count, 0 in 4a), a plain consistency line; empty state. Tests with overridden providers.
- **Task 9 — App shell Sleep→Stats + deep-link + device verify** (modify `app_shell.dart`): rename the Sleep tab to "Stats" hosting `StatsScreen`; wire `HomeScreen.onStreak` → switch to the Stats tab. Tests: Stats tab shows `StatsScreen`; the Home pill deep-links. Then the on-device verification protocol (create alarm → ring → dismiss → streak pill increments; miss → streak reflects it; stats screen populated).
