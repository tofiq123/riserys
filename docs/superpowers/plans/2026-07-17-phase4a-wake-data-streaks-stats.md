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

### Task 2: Streak engine (pure)

**Files:**
- Create: `lib/domain/streak.dart`
- Test: `test/domain/streak_test.dart`

**Interfaces:**
- Consumes: `WakeEvent` (Task 1) — `onTime`, `localDay`, `isOpen`.
- Produces:
  - `enum DayOutcome { success, miss, neutral, pending }`
  - `class StreakStats { final int current; final int best; final int freezesRemaining; final Map<DateTime, DayOutcome> byDay; static const empty; }` (const ctor; `byDay` keyed by local-midnight day; days absent = neutral).
  - `StreakStats computeStreak(List<WakeEvent> events, DateTime now, {int freezeCap = 2, int earnEvery = 7})`.

- [ ] **Step 1: Write the failing tests**

Create `test/domain/streak_test.dart` (uses **local** DateTimes so day-grouping is machine-timezone-independent):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/streak.dart';
import 'package:rise/domain/wake_event.dart';

void main() {
  DateTime d(int day) => DateTime(2026, 7, day); // local July 2026 midnights
  final now = DateTime(2026, 7, 20, 12); // "today" = July 20

  // A local event on the given day; on-time (dismissed +3m), late-miss (+30m),
  // or open (never dismissed).
  WakeEvent ev(int day, {required bool onTime, bool open = false}) {
    final ring = DateTime(2026, 7, day, 6);
    return WakeEvent(
      id: 0,
      alarmId: 1,
      scheduledAt: ring,
      firstRingAt: ring,
      dismissedAt: open ? null : ring.add(Duration(minutes: onTime ? 3 : 30)),
      onTime: onTime,
    );
  }

  test('empty log is all zero', () {
    final s = computeStreak([], now);
    expect(s.current, 0);
    expect(s.best, 0);
    expect(s.freezesRemaining, 0);
    expect(s.byDay, isEmpty);
  });

  test('consecutive on-time days build the streak', () {
    final s = computeStreak(
        [ev(17, onTime: true), ev(18, onTime: true), ev(19, onTime: true)], now);
    expect(s.current, 3);
    expect(s.best, 3);
    expect(s.byDay[d(18)], DayOutcome.success);
  });

  test('a miss breaks the streak when no freeze is banked', () {
    final s = computeStreak(
        [ev(17, onTime: true), ev(18, onTime: false), ev(19, onTime: true)], now);
    expect(s.current, 1); // 17 ok(1), 18 miss→0, 19 ok(1)
    expect(s.best, 1);
    expect(s.byDay[d(18)], DayOutcome.miss);
  });

  test('an earned freeze absorbs a miss and the streak holds', () {
    final days = [for (var i = 8; i <= 14; i++) ev(i, onTime: true)]; // 7 successes → 1 freeze
    days.add(ev(15, onTime: false)); // miss, absorbed
    days.add(ev(16, onTime: true)); // continues
    final s = computeStreak(days, now);
    expect(s.current, 8);
    expect(s.freezesRemaining, 0);
    expect(s.best, 8);
  });

  test('freezes are earned every 7 successes and cap at 2', () {
    final days = [for (var i = 1; i <= 14; i++) ev(i, onTime: true)]; // 14 straight
    final s = computeStreak(days, now);
    expect(s.current, 14);
    expect(s.freezesRemaining, 2);
  });

  test('no-alarm (neutral) days are skipped, not breaks', () {
    final s = computeStreak([ev(17, onTime: true), ev(19, onTime: true)], now); // 18 absent
    expect(s.current, 2);
    expect(s.byDay.containsKey(d(18)), isFalse);
  });

  test('today success extends the streak immediately', () {
    final s = computeStreak([ev(19, onTime: true), ev(20, onTime: true)], now);
    expect(s.current, 2);
    expect(s.byDay[d(20)], DayOutcome.success);
  });

  test('today pending holds the streak but does not extend it', () {
    final s = computeStreak(
        [ev(19, onTime: true), ev(20, onTime: false, open: true)], now);
    expect(s.current, 1);
    expect(s.byDay[d(20)], DayOutcome.pending);
  });

  test('a past never-dismissed event is a miss', () {
    final s = computeStreak(
        [ev(18, onTime: false, open: true), ev(19, onTime: true)], now);
    expect(s.byDay[d(18)], DayOutcome.miss);
    expect(s.current, 1);
  });

  test('any on-time event makes the whole day a success', () {
    final s = computeStreak(
        [ev(19, onTime: false), ev(19, onTime: true)], now);
    expect(s.byDay[d(19)], DayOutcome.success);
    expect(s.current, 1);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
flutter test test/domain/streak_test.dart
```
Expected: FAIL — `streak.dart` not found.

- [ ] **Step 3: Write the engine**

Create `lib/domain/streak.dart`:

```dart
import 'wake_event.dart';

/// How a single local calendar day is judged for the streak.
enum DayOutcome { success, miss, neutral, pending }

class StreakStats {
  const StreakStats({
    required this.current,
    required this.best,
    required this.freezesRemaining,
    required this.byDay,
  });

  final int current;
  final int best;
  final int freezesRemaining;

  /// Keyed by local-midnight day. Days absent from the map are neutral.
  final Map<DateTime, DayOutcome> byDay;

  static const empty = StreakStats(
      current: 0, best: 0, freezesRemaining: 0, byDay: <DateTime, DayOutcome>{});
}

/// Folds the wake-event log into streak stats. Pure and deterministic: the
/// streak is always recomputed from events, never stored, so it cannot desync.
///
/// - A day SUCCEEDS if it has any on-time event.
/// - A past day with rings but no on-time dismissal is a MISS.
/// - Today with rings but not yet an on-time success is PENDING (streak holds).
/// - A day with no events is NEUTRAL (absent from [StreakStats.byDay]; skipped).
/// - A freeze (earned 1 per [earnEvery] consecutive successes, capped at
///   [freezeCap]) is consumed by a miss before the streak breaks.
StreakStats computeStreak(
  List<WakeEvent> events,
  DateTime now, {
  int freezeCap = 2,
  int earnEvery = 7,
}) {
  final ln = now.toLocal();
  final today = DateTime(ln.year, ln.month, ln.day);

  // A day is on-time if ANY of its events is on-time.
  final hasOnTime = <DateTime, bool>{};
  for (final e in events) {
    final day = e.localDay;
    hasOnTime[day] = (hasOnTime[day] ?? false) || e.onTime;
  }

  final byDay = <DateTime, DayOutcome>{};
  hasOnTime.forEach((day, onTime) {
    if (day.isAfter(today)) return; // ignore future days (shouldn't occur)
    if (onTime) {
      byDay[day] = DayOutcome.success;
    } else if (day.isAtSameMomentAs(today)) {
      byDay[day] = DayOutcome.pending;
    } else {
      byDay[day] = DayOutcome.miss;
    }
  });

  // Fold every past day, plus today only once it is already a success.
  final foldDays = byDay.keys
      .where((day) => day.isBefore(today) || byDay[day] == DayOutcome.success)
      .toList()
    ..sort();

  var run = 0;
  var best = 0;
  var freezes = 0;
  for (final day in foldDays) {
    switch (byDay[day]) {
      case DayOutcome.success:
        run++;
        if (run % earnEvery == 0 && freezes < freezeCap) freezes++;
        if (run > best) best = run;
      case DayOutcome.miss:
        if (freezes > 0) {
          freezes--; // absorbed — the run holds
        } else {
          run = 0;
        }
      case DayOutcome.neutral:
      case DayOutcome.pending:
      case null:
        break;
    }
  }

  return StreakStats(
      current: run, best: best, freezesRemaining: freezes, byDay: byDay);
}
```

- [ ] **Step 4: Run to verify it passes**

```bash
flutter test test/domain/streak_test.dart
```
Expected: PASS — 10 tests green.

- [ ] **Step 5: Analyze and commit**

```bash
flutter analyze
git add lib/domain/streak.dart test/domain/streak_test.dart
git commit -m "feat(domain): add pure streak engine"
```

---

### Task 3: WakeEvents Drift table + v2→v3 migration

**Files:**
- Modify: `lib/data/local/database.dart`
- Regenerate: `lib/data/local/database.g.dart` (via build_runner)
- Modify: `test/data/migration_test.dart` (update the schemaVersion assertion + add v3 tests)

**Interfaces:**
- Produces: a Drift table `WakeEvents` (row class `WakeEventRow`) with columns `id`, `alarmId`, `scheduledAt`, `firstRingAt`, `dismissedAt?`, `method?`, `snoozeCount`, `missionFailures`, `onTime`, `label`; accessible as `db.wakeEvents` with `WakeEventsCompanion.insert(alarmId:, scheduledAt:, firstRingAt:, ...)`. `schemaVersion == 3`.

- [ ] **Step 1: Add the table + migration to `database.dart`**

In `lib/data/local/database.dart`, add the table class after the `Alarms` class (before `@DriftDatabase`):

```dart
/// One logical firing of an alarm — opened when the ring starts, finalised on
/// dismissal (added in schema v3). Independent of [Alarms]: deleting an alarm
/// does not delete its history.
@DataClassName('WakeEventRow')
class WakeEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get alarmId => integer()();
  DateTimeColumn get scheduledAt => dateTime()();
  DateTimeColumn get firstRingAt => dateTime()();
  DateTimeColumn get dismissedAt => dateTime().nullable()();
  TextColumn get method => text().nullable()();
  IntColumn get snoozeCount => integer().withDefault(const Constant(0))();
  IntColumn get missionFailures => integer().withDefault(const Constant(0))();
  BoolColumn get onTime => boolean().withDefault(const Constant(false))();
  TextColumn get label => text().withDefault(const Constant('Alarm'))();
}
```

Change the annotation to register it:

```dart
@DriftDatabase(tables: [Alarms, WakeEvents])
```

Bump the version:

```dart
  @override
  int get schemaVersion => 3;
```

Add the `from < 3` branch to `onUpgrade` (AFTER the existing `if (from < 2)` block, still inside the same `onUpgrade` closure):

```dart
          // v2 -> v3: the wake_events table. Idempotent like the column
          // migration above — a losing isolate (or a partial prior run) that
          // finds the table already present skips the create rather than
          // crashing on "table wake_events already exists".
          if (from < 3) {
            if (!await _tableExists('wake_events')) {
              await m.createTable(wakeEvents);
            }
          }
```

Add the helper next to `_columnNames`:

```dart
  /// Whether [table] exists, read from sqlite's own schema. Keeps the v3
  /// table-create migration idempotent under the app's multi-isolate DB opens.
  Future<bool> _tableExists(String table) async {
    final rows = await customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name = ?",
      variables: [Variable<String>(table)],
    ).get();
    return rows.isNotEmpty;
  }
```

- [ ] **Step 2: Regenerate the Drift code**

```bash
dart run build_runner build --delete-conflicting-outputs
```
Expected: succeeds; `lib/data/local/database.g.dart` now contains `WakeEvents`/`WakeEventRow`/`WakeEventsCompanion`. (If `dart run build_runner` isn't found, use `flutter pub run build_runner build --delete-conflicting-outputs`.)

- [ ] **Step 3: Update the existing migration test's version assertion**

In `test/data/migration_test.dart`, the first test (`upgrading a v1 database adds mission columns…`) asserts `expect(db.schemaVersion, 2);` — change it to:

```dart
    expect(db.schemaVersion, 3);
```
(The v1 DB now upgrades straight to v3; that test still only checks the alarms columns, which the v2 branch still adds.)

- [ ] **Step 4: Add the v3 migration tests**

Append these three tests inside `main()` in `test/data/migration_test.dart`:

```dart
  test('upgrading a v2 database adds wake_events and keeps existing alarms', () async {
    final raw = sqlite3.openInMemory();
    raw.execute('''
      CREATE TABLE alarms (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        hour INTEGER NOT NULL, minute INTEGER NOT NULL,
        days TEXT NOT NULL DEFAULT '', enabled INTEGER NOT NULL DEFAULT 1,
        label TEXT NOT NULL DEFAULT 'Alarm',
        sound_asset TEXT NOT NULL DEFAULT 'sounds/default_alarm.mp3',
        vibrate INTEGER NOT NULL DEFAULT 1, last_dismissed_at INTEGER,
        mission TEXT NOT NULL DEFAULT 'none', mission_diff TEXT NOT NULL DEFAULT 'easy',
        CHECK (hour BETWEEN 0 AND 23), CHECK (minute BETWEEN 0 AND 59)
      );
    ''');
    raw.execute("INSERT INTO alarms (hour, minute, label) VALUES (6, 30, 'Run');");
    raw.execute('PRAGMA user_version = 2;');

    final db = RiseDatabase(NativeDatabase.opened(raw));
    addTearDown(db.close);

    final alarms = await db.select(db.alarms).get();
    expect(alarms.single.label, 'Run', reason: 'alarms survive the upgrade');

    final id = await db.into(db.wakeEvents).insert(WakeEventsCompanion.insert(
      alarmId: 1,
      scheduledAt: DateTime.utc(2026, 7, 17, 6),
      firstRingAt: DateTime.utc(2026, 7, 17, 6),
    ));
    final ev = await (db.select(db.wakeEvents)..where((t) => t.id.equals(id))).getSingle();
    expect(ev.alarmId, 1);
    expect(ev.snoozeCount, 0, reason: 'new-column defaults');
    expect(ev.onTime, isFalse);
    expect(db.schemaVersion, 3);
  });

  test('upgrading to v3 is idempotent when wake_events already exists', () async {
    final raw = sqlite3.openInMemory();
    raw.execute('''
      CREATE TABLE alarms (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        hour INTEGER NOT NULL, minute INTEGER NOT NULL,
        days TEXT NOT NULL DEFAULT '', enabled INTEGER NOT NULL DEFAULT 1,
        label TEXT NOT NULL DEFAULT 'Alarm',
        sound_asset TEXT NOT NULL DEFAULT 'sounds/default_alarm.mp3',
        vibrate INTEGER NOT NULL DEFAULT 1, last_dismissed_at INTEGER,
        mission TEXT NOT NULL DEFAULT 'none', mission_diff TEXT NOT NULL DEFAULT 'easy',
        CHECK (hour BETWEEN 0 AND 23), CHECK (minute BETWEEN 0 AND 59)
      );
    ''');
    // wake_events already present (a losing isolate / partial prior run), but
    // user_version still says 2, so onUpgrade(2 -> 3) will run.
    raw.execute('''
      CREATE TABLE wake_events (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        alarm_id INTEGER NOT NULL,
        scheduled_at INTEGER NOT NULL,
        first_ring_at INTEGER NOT NULL,
        dismissed_at INTEGER,
        method TEXT,
        snooze_count INTEGER NOT NULL DEFAULT 0,
        mission_failures INTEGER NOT NULL DEFAULT 0,
        on_time INTEGER NOT NULL DEFAULT 0,
        label TEXT NOT NULL DEFAULT 'Alarm'
      );
    ''');
    raw.execute("INSERT INTO wake_events (alarm_id, scheduled_at, first_ring_at) VALUES (5, 0, 0);");
    raw.execute('PRAGMA user_version = 2;');

    final db = RiseDatabase(NativeDatabase.opened(raw));
    addTearDown(db.close);

    // Must not throw "table wake_events already exists"; the row is intact.
    final rows = await db.select(db.wakeEvents).get();
    expect(rows.single.alarmId, 5);
  });

  test('a fresh database is created at v3 with wake_events', () async {
    final db = RiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final id = await db.into(db.wakeEvents).insert(WakeEventsCompanion.insert(
      alarmId: 2,
      scheduledAt: DateTime.utc(2026, 7, 17, 6),
      firstRingAt: DateTime.utc(2026, 7, 17, 6),
    ));
    final ev = await (db.select(db.wakeEvents)..where((t) => t.id.equals(id))).getSingle();
    expect(ev.alarmId, 2);
  });
```

- [ ] **Step 5: Run the migration tests, whole suite, analyze**

```bash
flutter test test/data/migration_test.dart
flutter test
flutter analyze
```
Expected: migration tests green (the original 3 updated + 3 new); whole suite green; `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git add lib/data/local/database.dart lib/data/local/database.g.dart test/data/migration_test.dart
git commit -m "feat(data): add wake_events table with idempotent v3 migration"
```

---

### Task 4: WakeEventRepository

**Files:**
- Create: `lib/data/local/wake_event_repository.dart`
- Test: `test/data/wake_event_repository_test.dart`

**Interfaces:**
- Consumes: `RiseDatabase` + `db.wakeEvents`/`WakeEventRow`/`WakeEventsCompanion` (Task 3); `WakeEvent` (Task 1).
- Produces: `class WakeEventRepository` — `WakeEventRepository(RiseDatabase db)`; `static const reuseWindow = Duration(hours: 6)`, `static const grace = Duration(minutes: 15)`; `Future<int> openRing({required int alarmId, required DateTime scheduledAt, required DateTime firstRingAt, required String label})`; `Future<void> finalizeDismiss({required int alarmId, required DateTime dismissedAt, String? method})`; `Stream<List<WakeEvent>> watchAll()`; `Future<List<WakeEvent>> all()`.

- [ ] **Step 1: Write the failing test**

Create `test/data/wake_event_repository_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/local/database.dart';
import 'package:rise/data/local/wake_event_repository.dart';

void main() {
  late RiseDatabase db;
  late WakeEventRepository repo;

  setUp(() {
    db = RiseDatabase(NativeDatabase.memory());
    repo = WakeEventRepository(db);
  });
  tearDown(() => db.close());

  final ring = DateTime.utc(2026, 7, 17, 6, 0);

  test('openRing inserts a new open event', () async {
    final id = await repo.openRing(
        alarmId: 1, scheduledAt: ring, firstRingAt: ring, label: 'Run');
    final all = await repo.all();
    expect(all, hasLength(1));
    expect(all.single.id, id);
    expect(all.single.isOpen, isTrue);
    expect(all.single.label, 'Run');
  });

  test('openRing reuses an open event within the reuse window', () async {
    final id1 = await repo.openRing(
        alarmId: 1, scheduledAt: ring, firstRingAt: ring, label: 'Run');
    final id2 = await repo.openRing(
        alarmId: 1,
        scheduledAt: ring,
        firstRingAt: ring.add(const Duration(minutes: 9)),
        label: 'Run');
    expect(id2, id1);
    expect(await repo.all(), hasLength(1));
  });

  test('openRing starts a new event past the reuse window', () async {
    await repo.openRing(alarmId: 1, scheduledAt: ring, firstRingAt: ring, label: 'Run');
    await repo.openRing(
        alarmId: 1,
        scheduledAt: ring,
        firstRingAt: ring.add(const Duration(hours: 7)),
        label: 'Run');
    expect(await repo.all(), hasLength(2));
  });

  test('openRing does not reuse a different alarm\'s open event', () async {
    final a = await repo.openRing(alarmId: 1, scheduledAt: ring, firstRingAt: ring, label: 'A');
    final b = await repo.openRing(alarmId: 2, scheduledAt: ring, firstRingAt: ring, label: 'B');
    expect(b, isNot(a));
    expect(await repo.all(), hasLength(2));
  });

  test('finalizeDismiss within grace marks onTime true', () async {
    await repo.openRing(alarmId: 1, scheduledAt: ring, firstRingAt: ring, label: 'Run');
    await repo.finalizeDismiss(
        alarmId: 1,
        dismissedAt: ring.add(const Duration(minutes: 14, seconds: 59)),
        method: 'mission');
    final e = (await repo.all()).single;
    expect(e.isOpen, isFalse);
    expect(e.onTime, isTrue);
    expect(e.method, 'mission');
  });

  test('finalizeDismiss past grace marks onTime false', () async {
    await repo.openRing(alarmId: 1, scheduledAt: ring, firstRingAt: ring, label: 'Run');
    await repo.finalizeDismiss(
        alarmId: 1,
        dismissedAt: ring.add(const Duration(minutes: 15, seconds: 1)),
        method: 'slide');
    expect((await repo.all()).single.onTime, isFalse);
  });

  test('finalizeDismiss is a no-op when nothing is open', () async {
    await repo.finalizeDismiss(alarmId: 99, dismissedAt: ring, method: 'slide');
    expect(await repo.all(), isEmpty);
  });

  test('finalizeDismiss closes only the open event, leaving closed ones', () async {
    await repo.openRing(alarmId: 1, scheduledAt: ring, firstRingAt: ring, label: 'Run');
    await repo.finalizeDismiss(
        alarmId: 1, dismissedAt: ring.add(const Duration(minutes: 3)), method: 'mission');
    await repo.openRing(
        alarmId: 1,
        scheduledAt: ring,
        firstRingAt: ring.add(const Duration(hours: 24)),
        label: 'Run');
    await repo.finalizeDismiss(
        alarmId: 1,
        dismissedAt: ring.add(const Duration(hours: 24, minutes: 2)),
        method: 'slide');
    final all = await repo.all();
    expect(all, hasLength(2));
    expect(all.where((e) => e.isOpen), isEmpty);
    expect(all.map((e) => e.method).toSet(), {'mission', 'slide'});
  });
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
flutter test test/data/wake_event_repository_test.dart
```
Expected: FAIL — `wake_event_repository.dart` not found.

- [ ] **Step 3: Write the repository**

Create `lib/data/local/wake_event_repository.dart`:

```dart
import 'package:drift/drift.dart';

import '../../domain/wake_event.dart';
import 'database.dart';

/// Reads and writes wake events. Opens an event when a firing starts and
/// finalises it on dismissal; an event left open is a miss.
class WakeEventRepository {
  WakeEventRepository(this._db);

  final RiseDatabase _db;

  /// Two rings for the same alarm within this window are the same firing (a
  /// snooze re-fire or a ring-screen re-mount), not a new one.
  static const reuseWindow = Duration(hours: 6);

  /// Dismissing within this of the first ring counts as on time.
  static const grace = Duration(minutes: 15);

  static WakeEvent _toDomain(WakeEventRow r) => WakeEvent(
        id: r.id,
        alarmId: r.alarmId,
        scheduledAt: r.scheduledAt,
        firstRingAt: r.firstRingAt,
        dismissedAt: r.dismissedAt,
        method: r.method,
        snoozeCount: r.snoozeCount,
        missionFailures: r.missionFailures,
        onTime: r.onTime,
        label: r.label,
      );

  Future<WakeEventRow?> _openRowFor(int alarmId) =>
      (_db.select(_db.wakeEvents)
            ..where((t) => t.alarmId.equals(alarmId) & t.dismissedAt.isNull())
            ..orderBy([(t) => OrderingTerm.desc(t.firstRingAt)])
            ..limit(1))
          .getSingleOrNull();

  /// Opens (or reuses) the wake event for a firing; returns its id.
  Future<int> openRing({
    required int alarmId,
    required DateTime scheduledAt,
    required DateTime firstRingAt,
    required String label,
  }) async {
    final existing = await _openRowFor(alarmId);
    if (existing != null &&
        firstRingAt.toUtc().difference(existing.firstRingAt).abs() <=
            reuseWindow) {
      return existing.id;
    }
    return _db.into(_db.wakeEvents).insert(WakeEventsCompanion.insert(
          alarmId: alarmId,
          scheduledAt: scheduledAt.toUtc(),
          firstRingAt: firstRingAt.toUtc(),
          label: Value(label),
        ));
  }

  /// Finalises the open event for [alarmId]; no-op if none is open.
  Future<void> finalizeDismiss({
    required int alarmId,
    required DateTime dismissedAt,
    String? method,
  }) async {
    final open = await _openRowFor(alarmId);
    if (open == null) return;
    final onTime =
        dismissedAt.toUtc().difference(open.firstRingAt) <= grace;
    await (_db.update(_db.wakeEvents)..where((t) => t.id.equals(open.id))).write(
      WakeEventsCompanion(
        dismissedAt: Value(dismissedAt.toUtc()),
        method: Value(method),
        onTime: Value(onTime),
      ),
    );
  }

  Stream<List<WakeEvent>> watchAll() => (_db.select(_db.wakeEvents)
        ..orderBy([(t) => OrderingTerm.desc(t.firstRingAt)]))
      .watch()
      .map((rows) => rows.map(_toDomain).toList());

  Future<List<WakeEvent>> all() async {
    final rows = await (_db.select(_db.wakeEvents)
          ..orderBy([(t) => OrderingTerm.desc(t.firstRingAt)]))
        .get();
    return rows.map(_toDomain).toList();
  }
}
```

- [ ] **Step 4: Run to verify it passes**

```bash
flutter test test/data/wake_event_repository_test.dart
```
Expected: PASS — 8 tests green.

- [ ] **Step 5: Whole suite, analyze, commit**

```bash
flutter test
flutter analyze
git add lib/data/local/wake_event_repository.dart test/data/wake_event_repository_test.dart
git commit -m "feat(data): add WakeEventRepository (open-on-ring, finalize-on-dismiss)"
```

---

### Task 5: WakeRecorder + Riverpod providers

**Files:**
- Modify: `lib/data/local/alarm_repository.dart` (expose the shared `RiseDatabase`)
- Create: `lib/data/wake_recorder.dart`
- Create: `lib/ui/state/wake_providers.dart`
- Test: `test/data/wake_recorder_test.dart`
- Test: `test/ui/state/wake_providers_test.dart`

**Interfaces:**
- Consumes: `WakeEventRepository` (Task 4), `AlarmRepository` (`all()`, and a new `database` getter), `computeStreak`/`StreakStats` (Task 2), `WakeEvent` (Task 1), `alarmRepositoryProvider` (existing, `lib/ui/state/alarm_providers.dart`).
- Produces:
  - `RiseDatabase get database` on `AlarmRepository`.
  - `class WakeRecorder` — `WakeRecorder(WakeEventRepository events, AlarmRepository alarms)`; `Future<void> openRing(int alarmId)`; `Future<void> finalizeDismiss(int alarmId, {String? method})`.
  - Providers: `wakeEventRepositoryProvider` (`Provider<WakeEventRepository>`), `wakeRecorderProvider` (`Provider<WakeRecorder>`), `wakeEventsProvider` (`StreamProvider<List<WakeEvent>>`), `streakProvider` (`Provider<StreakStats>`).

- [ ] **Step 1: Expose the database on AlarmRepository**

In `lib/data/local/alarm_repository.dart`, add this getter (just after the `final RiseDatabase _db;` field, near the top of the class):

```dart
  /// The underlying database, so a sibling repository (e.g. WakeEventRepository)
  /// can be built over the SAME handle — two handles to the file would drift.
  RiseDatabase get database => _db;
```

- [ ] **Step 2: Write the failing WakeRecorder test**

Create `test/data/wake_recorder_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/local/alarm_repository.dart';
import 'package:rise/data/local/database.dart';
import 'package:rise/data/local/wake_event_repository.dart';
import 'package:rise/data/wake_recorder.dart';
import 'package:rise/domain/alarm.dart';

void main() {
  late RiseDatabase db;
  late WakeEventRepository events;
  late AlarmRepository alarms;
  late WakeRecorder rec;

  setUp(() {
    db = RiseDatabase(NativeDatabase.memory());
    events = WakeEventRepository(db);
    alarms = AlarmRepository(db);
    rec = WakeRecorder(events, alarms);
  });
  tearDown(() => db.close());

  test('openRing opens an event with the alarm label and today\'s scheduled time',
      () async {
    final saved =
        await alarms.upsert(const Alarm(id: 0, hour: 6, minute: 30, label: 'Run'));
    await rec.openRing(saved.id);
    final all = await events.all();
    expect(all, hasLength(1));
    final e = all.single;
    expect(e.alarmId, saved.id);
    expect(e.label, 'Run');
    expect(e.isOpen, isTrue);
    final s = e.scheduledAt.toLocal();
    expect(s.hour, 6);
    expect(s.minute, 30);
  });

  test('finalizeDismiss closes the open event with the method', () async {
    final saved =
        await alarms.upsert(const Alarm(id: 0, hour: 6, minute: 30, label: 'Run'));
    await rec.openRing(saved.id);
    await rec.finalizeDismiss(saved.id, method: 'mission');
    final e = (await events.all()).single;
    expect(e.isOpen, isFalse);
    expect(e.method, 'mission');
  });

  test('openRing for an unknown alarm falls back to a default label', () async {
    await rec.openRing(999);
    final e = (await events.all()).single;
    expect(e.label, 'Alarm');
    expect(e.alarmId, 999);
  });
}
```

- [ ] **Step 3: Run to verify it fails**

```bash
flutter test test/data/wake_recorder_test.dart
```
Expected: FAIL — `wake_recorder.dart` not found (and/or `database` getter missing).

- [ ] **Step 4: Write WakeRecorder**

Create `lib/data/wake_recorder.dart`:

```dart
import 'package:collection/collection.dart';

import 'local/alarm_repository.dart';
import 'local/wake_event_repository.dart';

/// Bridges the ring flow to the wake-event log: opens an event when an alarm
/// starts ringing and finalises it on dismissal. Callers invoke these
/// best-effort — a stats-write failure must never block the ring.
class WakeRecorder {
  WakeRecorder(this._events, this._alarms);

  final WakeEventRepository _events;
  final AlarmRepository _alarms;

  Future<void> openRing(int alarmId) async {
    final alarm = (await _alarms.all()).firstWhereOrNull((a) => a.id == alarmId);
    final now = DateTime.now();
    await _events.openRing(
      alarmId: alarmId,
      scheduledAt: _scheduledFor(alarm?.hour, alarm?.minute, now),
      firstRingAt: now,
      label: alarm?.label ?? 'Alarm',
    );
  }

  Future<void> finalizeDismiss(int alarmId, {String? method}) =>
      _events.finalizeDismiss(
          alarmId: alarmId, dismissedAt: DateTime.now(), method: method);

  /// The alarm's scheduled instant for the firing that just happened: today's
  /// local h:m, falling back to [now] when the alarm can't be found.
  static DateTime _scheduledFor(int? hour, int? minute, DateTime now) {
    if (hour == null || minute == null) return now;
    final l = now.toLocal();
    return DateTime(l.year, l.month, l.day, hour, minute);
  }
}
```

- [ ] **Step 5: Run to verify it passes**

```bash
flutter test test/data/wake_recorder_test.dart
```
Expected: PASS — 3 tests green.

- [ ] **Step 6: Write the providers + their test**

Create `lib/ui/state/wake_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/wake_event_repository.dart';
import '../../data/wake_recorder.dart';
import '../../domain/streak.dart';
import '../../domain/wake_event.dart';
import 'alarm_providers.dart';

/// The wake-event store, built over the same database handle the alarm
/// repository uses.
final wakeEventRepositoryProvider = Provider<WakeEventRepository>(
    (ref) => WakeEventRepository(ref.watch(alarmRepositoryProvider).database));

final wakeRecorderProvider = Provider<WakeRecorder>((ref) => WakeRecorder(
    ref.watch(wakeEventRepositoryProvider), ref.watch(alarmRepositoryProvider)));

final wakeEventsProvider = StreamProvider<List<WakeEvent>>(
    (ref) => ref.watch(wakeEventRepositoryProvider).watchAll());

/// The streak recomputed from the live event log.
final streakProvider = Provider<StreakStats>((ref) {
  final events = ref.watch(wakeEventsProvider).value ?? const <WakeEvent>[];
  return computeStreak(events, DateTime.now());
});
```

Create `test/ui/state/wake_providers_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/wake_event.dart';
import 'package:rise/ui/state/wake_providers.dart';

void main() {
  test('streakProvider is empty with no events', () async {
    final c = ProviderContainer(overrides: [
      wakeEventsProvider.overrideWith((ref) => Stream.value(const <WakeEvent>[])),
    ]);
    addTearDown(c.dispose);
    await c.read(wakeEventsProvider.future);
    expect(c.read(streakProvider).current, 0);
  });

  test('streakProvider counts an on-time event today as a streak of 1', () async {
    final today = DateTime.now();
    final e = WakeEvent(
      id: 1,
      alarmId: 1,
      scheduledAt: today,
      firstRingAt: today,
      dismissedAt: today.add(const Duration(minutes: 2)),
      onTime: true,
    );
    final c = ProviderContainer(overrides: [
      wakeEventsProvider.overrideWith((ref) => Stream.value([e])),
    ]);
    addTearDown(c.dispose);
    await c.read(wakeEventsProvider.future);
    expect(c.read(streakProvider).current, 1);
  });
}
```

- [ ] **Step 7: Run providers test, whole suite, analyze, commit**

```bash
flutter test test/ui/state/wake_providers_test.dart
flutter test
flutter analyze
git add lib/data/local/alarm_repository.dart lib/data/wake_recorder.dart lib/ui/state/wake_providers.dart test/data/wake_recorder_test.dart test/ui/state/wake_providers_test.dart
git commit -m "feat(data): add WakeRecorder and wake/streak providers"
```

---

### Task 6: Wire recording into the ring flow

**Files:**
- Modify: `lib/ui/screens/ring_screen.dart`
- Modify: `lib/main.dart` (the real ring records)
- Test: `test/ui/screens/ring_screen_test.dart` (add recording tests)

**Interfaces:**
- Consumes: `wakeRecorderProvider` (Task 5); the existing `RingScreen`/`dismissRingingAlarm`.
- Produces: `RingScreen` gains `bool record` (default false); when true it opens a wake event on mount and finalises it (with the dismissal `method`) on a successful dismiss — both best-effort. `_dismiss` now takes the method. `main._showRing` passes `record: true`.

> Recording is best-effort: a wake-log failure is caught and logged, never thrown into the ring/dismiss path (the alarm must always be stoppable). Previews (app shell) leave `record` at its default `false`, so they never touch the wake log.

- [ ] **Step 1: Add the failing recording tests**

In `test/ui/screens/ring_screen_test.dart`, add these imports at the top (alongside the existing ones):

```dart
import 'package:rise/data/wake_recorder.dart';
import 'package:rise/ui/state/wake_providers.dart';
```

Add this fake recorder above `void main()` (after the existing top-level helpers):

```dart
class _RecordingRecorder implements WakeRecorder {
  final opened = <int>[];
  final finalized = <(int, String?)>[];
  @override
  Future<void> openRing(int alarmId) async => opened.add(alarmId);
  @override
  Future<void> finalizeDismiss(int alarmId, {String? method}) async =>
      finalized.add((alarmId, method));
}
```

Add these three tests inside `main()`:

```dart
  testWidgets('with record: opens on mount and finalizes "slide" on a slide dismiss',
      (t) async {
    final rec = _RecordingRecorder();
    await t.pumpWidget(ProviderScope(
      overrides: [
        alarmsProvider.overrideWith((ref) => Stream.value(
            const [Alarm(id: 5, hour: 6, minute: 30, label: 'Run')])),
        wakeRecorderProvider.overrideWithValue(rec),
      ],
      child: MaterialApp(
        home: RingScreen(alarmId: 5, record: true, dismissAlarm: (_) async {}),
      ),
    ));
    await t.pump();
    expect(rec.opened, [5]);
    await t.drag(find.byType(SlideToWake), const Offset(1000, 0));
    await t.pump();
    await t.pump(const Duration(milliseconds: 20));
    expect(rec.finalized, [(5, 'slide')]);
  });

  testWidgets('with record: a missioned dismiss finalizes with method "mission"',
      (t) async {
    final rec = _RecordingRecorder();
    await t.pumpWidget(ProviderScope(
      overrides: [
        alarmsProvider.overrideWith((ref) => Stream.value(
            const [Alarm(id: 7, hour: 6, minute: 30, mission: 'math')])),
        wakeRecorderProvider.overrideWithValue(rec),
      ],
      child: MaterialApp(
        home: RingScreen(
          alarmId: 7,
          record: true,
          dismissAlarm: (_) async {},
          missionBuilder: (context, alarm, onSolved) =>
              TextButton(onPressed: onSolved, child: const Text('SOLVE')),
        ),
      ),
    ));
    await t.pump();
    expect(rec.opened, [7]);
    await t.tap(find.text('SOLVE'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 20));
    expect(rec.finalized, [(7, 'mission')]);
  });

  testWidgets('without record (default): never touches the wake recorder', (t) async {
    final rec = _RecordingRecorder();
    await t.pumpWidget(ProviderScope(
      overrides: [
        alarmsProvider.overrideWith((ref) => Stream.value(
            const [Alarm(id: 5, hour: 6, minute: 30)])),
        wakeRecorderProvider.overrideWithValue(rec),
      ],
      child: MaterialApp(
        home: RingScreen(alarmId: 5, dismissAlarm: (_) async {}),
      ),
    ));
    await t.pump();
    await t.drag(find.byType(SlideToWake), const Offset(1000, 0));
    await t.pump();
    await t.pump(const Duration(milliseconds: 20));
    expect(rec.opened, isEmpty);
    expect(rec.finalized, isEmpty);
  });
```

- [ ] **Step 2: Run to verify it fails**

```bash
flutter test test/ui/screens/ring_screen_test.dart
```
Expected: FAIL — `RingScreen` has no `record` parameter.

- [ ] **Step 3: Wire recording into `ring_screen.dart`**

Add the import (with the other `../state/...` imports):

```dart
import '../state/wake_providers.dart';
```

Add the `record` field to the constructor and class. Change the constructor to:

```dart
  const RingScreen({
    super.key,
    required this.alarmId,
    this.onDismissed,
    this.dismissAlarm = dismissRingingAlarm,
    this.missionBuilder,
    this.record = false,
  });
```

And add the field (after `missionBuilder`):

```dart
  /// When true, this firing is logged to the wake-event store — opened on
  /// mount, finalised on dismiss. Off for previews. Best-effort: a wake-log
  /// failure is logged, never thrown into the ring.
  final bool record;
```

In `initState`, after the `_clock = Timer.periodic(...)` block, add:

```dart
    if (widget.record) _recordRingStart();
```

Add this method (e.g. after `dispose`):

```dart
  Future<void> _recordRingStart() async {
    try {
      await ref.read(wakeRecorderProvider).openRing(widget.alarmId);
    } catch (e) {
      debugPrint('Rise: wake-open failed for ${widget.alarmId}: $e');
    }
  }
```

Replace the whole `_dismiss` method with the method-carrying, recording version:

```dart
  Future<void> _dismiss(String method) async {
    if (_dismissing) return; // guard double-taps / repeated slide fires
    setState(() => _dismissing = true);
    try {
      await widget.dismissAlarm(widget.alarmId);
    } catch (e) {
      debugPrint('Rise: dismiss failed for ${widget.alarmId}: $e');
      if (mounted) {
        setState(() {
          _dismissing = false;
          _attempt++; // fresh key resets the slide-to-wake so it can fire again
        });
      }
      return;
    }
    if (widget.record) {
      try {
        await ref
            .read(wakeRecorderProvider)
            .finalizeDismiss(widget.alarmId, method: method);
      } catch (e) {
        debugPrint('Rise: wake-finalize failed for ${widget.alarmId}: $e');
      }
    }
    if (!mounted) return;
    widget.onDismissed?.call();
  }
```

In `build`, change the gate's two `_dismiss` references to pass the method:

```dart
          ? widget.missionBuilder!(context, alarm, () => _dismiss('mission'))
          : SlideToWake(onWake: () => _dismiss('slide')),
```

- [ ] **Step 4: Make the real ring record in `main.dart`**

In `lib/main.dart`, `_showRing` builds the `RingScreen`. Add `record: true`:

```dart
    final route = MaterialPageRoute<void>(
      builder: (_) => RingScreen(
        alarmId: alarmId,
        record: true,
        missionBuilder: buildMission,
        onDismissed: () => _navigatorKey.currentState?.maybePop(),
      ),
    );
```

- [ ] **Step 5: Run the ring tests to verify they pass**

```bash
flutter test test/ui/screens/ring_screen_test.dart
```
Expected: PASS — the existing ring tests plus the 3 new recording tests (uses `pump`, not `pumpAndSettle`).

- [ ] **Step 6: Whole suite, analyze, commit**

```bash
flutter test
flutter analyze
git add lib/ui/screens/ring_screen.dart lib/main.dart test/ui/screens/ring_screen_test.dart
git commit -m "feat(ui): record wake events from the ring flow (open on ring, finalize on dismiss)"
```

---

### Task 7: Live Home streak pill

**Files:**
- Modify: `lib/ui/screens/home_screen.dart`
- Modify: `test/ui/screens/home_screen_test.dart`
- Modify: `test/ui/screens/app_shell_test.dart` (add the `streakProvider` override so it keeps passing)

**Interfaces:**
- Consumes: `streakProvider` (Task 5).
- Produces: `HomeScreen` gains `VoidCallback? onStreak`; the header renders a live flame+count pill from `streakProvider` (muted "Start" at 0) that calls `onStreak` when tapped.

> `HomeScreen` now reads `streakProvider`, whose default chain reaches the (test-unconfigured) alarm service — so every test that renders `HomeScreen` must override `streakProvider`. This task adds that override to both `home_screen_test.dart` and `app_shell_test.dart`. `onStreak` is nullable; the app shell wires the real deep-link in Task 9 (until then the pill is inert, which is fine).

- [ ] **Step 1: Edit `home_screen.dart`**

Add the import (after the existing `import '../state/alarm_providers.dart';`):

```dart
import '../state/wake_providers.dart';
```

Change the constructor + fields — replace:

```dart
  const HomeScreen({
    super.key,
    required this.onNew,
    required this.onEdit,
    required this.onPreview,
  });

  final VoidCallback onNew;
  final void Function(Alarm) onEdit;
  final VoidCallback onPreview;
```

with:

```dart
  const HomeScreen({
    super.key,
    required this.onNew,
    required this.onEdit,
    required this.onPreview,
    this.onStreak,
  });

  final VoidCallback onNew;
  final void Function(Alarm) onEdit;
  final VoidCallback onPreview;

  /// Opens Stats (the app shell switches tab). Null leaves the pill inert.
  final VoidCallback? onStreak;
```

Replace the whole `_header()` method with the pill-carrying header plus a `_streakPill()` method:

```dart
  Widget _header() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: Text(_greeting(),
              style: RiseText.display, overflow: TextOverflow.ellipsis),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _streakPill(),
            const SizedBox(width: 10),
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                  color: RiseColors.primary, shape: BoxShape.circle),
              child: const Icon(Icons.person,
                  color: RiseColors.primaryText, size: 20),
            ),
          ],
        ),
      ],
    );
  }

  Widget _streakPill() {
    final streak = ref.watch(streakProvider);
    final has = streak.current > 0;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onStreak,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: has ? RiseColors.accentSoft : RiseColors.surface2,
          borderRadius: BorderRadius.circular(RiseRadii.pill),
          border: Border.all(color: RiseColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_fire_department,
                size: 16,
                color: has ? RiseColors.waking : RiseColors.textFaint),
            const SizedBox(width: 5),
            Text(has ? '${streak.current}' : 'Start',
                style: RiseText.mono(
                    size: 14,
                    weight: FontWeight.w700,
                    color: has ? RiseColors.text : RiseColors.textDim)),
          ],
        ),
      ),
    );
  }
```

- [ ] **Step 2: Update `home_screen_test.dart`**

Add these imports (after `import 'package:rise/ui/state/alarm_providers.dart';`):

```dart
import 'package:rise/domain/streak.dart';
import 'package:rise/ui/state/wake_providers.dart';
```

Replace the `_host` function with (adds `streak` + `onStreak`, overrides `streakProvider`):

```dart
Widget _host({
  required List<Alarm> alarms,
  required _RecordingMutations mutations,
  VoidCallback? onNew,
  void Function(Alarm)? onEdit,
  VoidCallback? onStreak,
  StreakStats streak = StreakStats.empty,
}) {
  return ProviderScope(
    overrides: [
      alarmsProvider.overrideWith((ref) => Stream.value(alarms)),
      nextOccurrenceProvider.overrideWith((ref) async => null),
      alarmMutationsProvider.overrideWithValue(mutations),
      streakProvider.overrideWithValue(streak),
    ],
    child: MaterialApp(
      home: HomeScreen(
        onNew: onNew ?? () {},
        onEdit: onEdit ?? (_) {},
        onPreview: () {},
        onStreak: onStreak,
      ),
    ),
  );
}
```

Add these three tests inside `main()`:

```dart
  testWidgets('the streak pill shows the current streak', (t) async {
    await t.pumpWidget(_host(
      alarms: const [],
      mutations: _RecordingMutations(),
      streak: const StreakStats(
          current: 5, best: 7, freezesRemaining: 1, byDay: {}),
    ));
    await t.pump();
    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('the streak pill shows Start when there is no streak', (t) async {
    await t.pumpWidget(
        _host(alarms: const [], mutations: _RecordingMutations()));
    await t.pump();
    expect(find.text('Start'), findsOneWidget);
  });

  testWidgets('tapping the streak pill calls onStreak', (t) async {
    var tapped = false;
    await t.pumpWidget(_host(
      alarms: const [],
      mutations: _RecordingMutations(),
      streak: const StreakStats(
          current: 3, best: 3, freezesRemaining: 0, byDay: {}),
      onStreak: () => tapped = true,
    ));
    await t.pump();
    await t.tap(find.text('3'));
    await t.pump();
    expect(tapped, isTrue);
  });
```

- [ ] **Step 3: Update `app_shell_test.dart`**

Add these imports (after `import 'package:rise/ui/state/alarm_providers.dart';`):

```dart
import 'package:rise/domain/streak.dart';
import 'package:rise/ui/state/wake_providers.dart';
```

Add the `streakProvider` override to `_overrides` — replace:

```dart
List<Override> _overrides(List<Alarm> alarms, ScheduledOccurrence? next) => [
      alarmsProvider.overrideWith((ref) => Stream.value(alarms)),
      nextOccurrenceProvider.overrideWith((ref) async => next),
    ];
```

with:

```dart
List<Override> _overrides(List<Alarm> alarms, ScheduledOccurrence? next) => [
      alarmsProvider.overrideWith((ref) => Stream.value(alarms)),
      nextOccurrenceProvider.overrideWith((ref) async => next),
      streakProvider.overrideWithValue(StreakStats.empty),
    ];
```

- [ ] **Step 4: Run the affected tests, whole suite, analyze**

```bash
flutter test test/ui/screens/home_screen_test.dart test/ui/screens/app_shell_test.dart
flutter test
flutter analyze
```
Expected: Home tests (existing + 3 new) and app-shell tests all green; whole suite green; `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/screens/home_screen.dart test/ui/screens/home_screen_test.dart test/ui/screens/app_shell_test.dart
git commit -m "feat(ui): make the Home streak pill live and tappable"
```

---

### Task 8: Stats screen

**Files:**
- Create: `lib/ui/screens/stats_screen.dart`
- Test: `test/ui/screens/stats_screen_test.dart`

**Interfaces:**
- Consumes: `streakProvider` + `wakeEventsProvider` (Task 5), `StreakStats`/`DayOutcome` (Task 2), `WakeEvent` (Task 1); `RiseCard`, `SectionLabel`, tokens/typography.
- Produces:
  - Top-level pure helpers `List<DayWake> weekWakes(List<WakeEvent> events, DateTime now)` and `String consistencyLine(List<WakeEvent> events, DateTime now)`; `class DayWake { final DateTime day; final int? deltaMinutes; final bool onTime; final bool hasEvent; }`.
  - `class StatsScreen extends ConsumerWidget` — a streak card (current/best/freezes), a 30-day on-time calendar, a "this week" consistency line + 7-bar wake-vs-set chart; an empty state when there are no events.

- [ ] **Step 1: Write the failing test**

Create `test/ui/screens/stats_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/streak.dart';
import 'package:rise/domain/wake_event.dart';
import 'package:rise/ui/screens/stats_screen.dart';
import 'package:rise/ui/state/wake_providers.dart';

WakeEvent evOn(DateTime day, {bool onTime = true}) {
  final ring = DateTime(day.year, day.month, day.day, 6);
  return WakeEvent(
    id: 0,
    alarmId: 1,
    scheduledAt: ring,
    firstRingAt: ring,
    dismissedAt: ring.add(Duration(minutes: onTime ? 3 : 30)),
    onTime: onTime,
    label: 'Run',
  );
}

Future<void> _pump(WidgetTester t, Widget w) async {
  t.view.physicalSize = const Size(1200, 4000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(w);
}

Widget _host({List<WakeEvent> events = const [], StreakStats streak = StreakStats.empty}) {
  return ProviderScope(
    overrides: [
      wakeEventsProvider.overrideWith((ref) => Stream.value(events)),
      streakProvider.overrideWithValue(streak),
    ],
    child: const MaterialApp(home: Scaffold(body: StatsScreen())),
  );
}

void main() {
  testWidgets('shows an empty state when there are no wake events', (t) async {
    await _pump(t, _host());
    await t.pump();
    expect(find.textContaining('No wake data'), findsOneWidget);
  });

  testWidgets('renders the streak card and section headers with data', (t) async {
    final today = DateTime.now();
    await _pump(t, _host(
      events: [evOn(today)],
      streak: const StreakStats(current: 4, best: 9, freezesRemaining: 1, byDay: {}),
    ));
    await t.pump();
    expect(find.text('4'), findsOneWidget); // current streak
    expect(find.text('9'), findsOneWidget); // best
    expect(find.text('LAST 30 DAYS'), findsOneWidget); // SectionLabel uppercases
    expect(find.text('THIS WEEK'), findsOneWidget);
  });

  test('consistencyLine reports the on-time count for the week', () {
    final now = DateTime(2026, 7, 20, 12);
    final events = [
      evOn(DateTime(2026, 7, 18)),
      evOn(DateTime(2026, 7, 19), onTime: false),
      evOn(DateTime(2026, 7, 20)),
    ];
    expect(consistencyLine(events, now), 'On time 2 of 3 this week.');
  });

  test('consistencyLine handles a week with no wake-ups', () {
    expect(consistencyLine(const [], DateTime(2026, 7, 20, 12)),
        'No wake-ups yet this week.');
  });

  test('weekWakes returns 7 days ending today, with per-day deltas', () {
    final now = DateTime(2026, 7, 20, 12);
    final wakes = weekWakes([evOn(DateTime(2026, 7, 20))], now);
    expect(wakes, hasLength(7));
    expect(wakes.last.day, DateTime(2026, 7, 20));
    expect(wakes.last.hasEvent, isTrue);
    expect(wakes.last.deltaMinutes, 3);
    expect(wakes.first.hasEvent, isFalse); // 6 days ago: no event
  });
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
flutter test test/ui/screens/stats_screen_test.dart
```
Expected: FAIL — `stats_screen.dart` not found.

- [ ] **Step 3: Write the Stats screen**

Create `lib/ui/screens/stats_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/streak.dart';
import '../../domain/wake_event.dart';
import '../components/rise_card.dart';
import '../components/section_label.dart';
import '../state/wake_providers.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

DateTime _todayLocal(DateTime now) {
  final l = now.toLocal();
  return DateTime(l.year, l.month, l.day);
}

DateTime _dayOf(DateTime t) {
  final l = t.toLocal();
  return DateTime(l.year, l.month, l.day);
}

/// The representative wake for one local day.
class DayWake {
  const DayWake(this.day,
      {this.deltaMinutes, required this.onTime, required this.hasEvent});

  final DateTime day;

  /// dismissed − scheduled, in minutes; null when the day had no dismissal.
  final int? deltaMinutes;
  final bool onTime;
  final bool hasEvent;
}

/// The last 7 local days (oldest first), each with its representative wake:
/// the on-time event if any, else the latest event.
List<DayWake> weekWakes(List<WakeEvent> events, DateTime now) {
  final today = _todayLocal(now);
  final byDay = <DateTime, WakeEvent>{};
  for (final e in events) {
    final d = _dayOf(e.firstRingAt);
    final cur = byDay[d];
    final better = cur == null ||
        (e.onTime && !cur.onTime) ||
        (e.onTime == cur.onTime && e.firstRingAt.isAfter(cur.firstRingAt));
    if (better) byDay[d] = e;
  }
  return [
    for (var i = 6; i >= 0; i--)
      () {
        final day = today.subtract(Duration(days: i));
        final e = byDay[day];
        if (e == null) return DayWake(day, onTime: false, hasEvent: false);
        final delta = e.dismissedAt?.difference(e.scheduledAt).inMinutes;
        return DayWake(day,
            deltaMinutes: delta, onTime: e.onTime, hasEvent: true);
      }(),
  ];
}

/// "On time X of Y this week", or a no-data line.
String consistencyLine(List<WakeEvent> events, DateTime now) {
  final wakes = weekWakes(events, now);
  final rang = wakes.where((w) => w.hasEvent).length;
  final onTime = wakes.where((w) => w.onTime).length;
  if (rang == 0) return 'No wake-ups yet this week.';
  return 'On time $onTime of $rang this week.';
}

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streak = ref.watch(streakProvider);
    final events = ref.watch(wakeEventsProvider).value ?? const <WakeEvent>[];
    final now = DateTime.now();

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            RiseSpacing.screen, 8, RiseSpacing.screen, 40),
        children: [
          Text('Stats', style: RiseText.display),
          const SizedBox(height: 16),
          if (events.isEmpty)
            _empty()
          else ...[
            _streakCard(streak),
            const SizedBox(height: 24),
            const SectionLabel('Last 30 days'),
            const SizedBox(height: 12),
            _calendar(streak.byDay, now),
            const SizedBox(height: 24),
            const SectionLabel('This week'),
            const SizedBox(height: 6),
            Text(consistencyLine(events, now), style: RiseText.caption),
            const SizedBox(height: 14),
            _weekChart(weekWakes(events, now)),
          ],
        ],
      ),
    );
  }

  Widget _empty() => RiseCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
          child: Column(
            children: [
              const Icon(Icons.local_fire_department,
                  size: 40, color: RiseColors.textFaint),
              const SizedBox(height: 12),
              Text('No wake data yet',
                  style: RiseText.body.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Set an alarm and wake up on time to start your streak.',
                  textAlign: TextAlign.center, style: RiseText.caption),
            ],
          ),
        ),
      );

  Widget _streakCard(StreakStats s) => RiseCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Icon(Icons.local_fire_department,
                      color: RiseColors.waking, size: 30),
                ),
                const SizedBox(width: 8),
                Text('${s.current}',
                    style: RiseText.mono(size: 52, weight: FontWeight.w600)),
                const SizedBox(width: 8),
                Text(s.current == 1 ? 'day' : 'days',
                    style: RiseText.body.copyWith(color: RiseColors.textDim)),
              ],
            ),
            const SizedBox(height: 4),
            Text('current streak', style: RiseText.caption),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _miniStat('Best', '${s.best}'),
                Container(width: 1, height: 32, color: RiseColors.divider),
                _miniStat('Freezes', '${s.freezesRemaining}'),
              ],
            ),
          ],
        ),
      );

  Widget _miniStat(String label, String value) => Column(
        children: [
          Text(value, style: RiseText.mono(size: 22, weight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(label, style: RiseText.caption),
        ],
      );

  Widget _calendar(Map<DateTime, DayOutcome> byDay, DateTime now) {
    final today = _todayLocal(now);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var i = 29; i >= 0; i--)
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: _cellColor(byDay[today.subtract(Duration(days: i))]),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: RiseColors.border),
            ),
          ),
      ],
    );
  }

  Color _cellColor(DayOutcome? o) => switch (o) {
        DayOutcome.success => RiseColors.positive,
        DayOutcome.miss => RiseColors.danger,
        DayOutcome.pending => RiseColors.waking,
        DayOutcome.neutral || null => RiseColors.surface2,
      };

  Widget _weekChart(List<DayWake> wakes) {
    const maxMin = 30.0;
    const maxH = 64.0;
    return SizedBox(
      height: 100,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final w in wakes)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    width: 18,
                    height: w.deltaMinutes == null
                        ? 4
                        : 6 +
                            (w.deltaMinutes!.clamp(0, maxMin) / maxMin) * maxH,
                    decoration: BoxDecoration(
                      color: w.hasEvent
                          ? (w.onTime ? RiseColors.positive : RiseColors.danger)
                          : RiseColors.border,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(_weekdayLetter(w.day),
                      style: RiseText.caption.copyWith(fontSize: 10)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _weekdayLetter(DateTime day) {
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S']; // Mon..Sun
    return letters[(day.weekday - 1) % 7];
  }
}
```

- [ ] **Step 4: Run the stats test to verify it passes**

```bash
flutter test test/ui/screens/stats_screen_test.dart
```
Expected: PASS — 5 tests green (2 widget, 3 pure).

- [ ] **Step 5: Whole suite, analyze, commit**

```bash
flutter test
flutter analyze
git add lib/ui/screens/stats_screen.dart test/ui/screens/stats_screen_test.dart
git commit -m "feat(ui): add the Stats screen (streak, calendar, week chart)"
```

---

### Task 9: App shell Sleep→Stats + deep-link + device verify

**Files:**
- Modify: `lib/ui/screens/app_shell.dart`
- Modify: `test/ui/screens/app_shell_test.dart`

**Interfaces:**
- Consumes: `StatsScreen` (Task 8); the existing `HomeScreen.onStreak` (Task 7).
- Produces: the stubbed **Sleep** tab (index 2) becomes **Stats** hosting `StatsScreen`; the Home streak pill deep-links to it.

- [ ] **Step 1: Edit `app_shell.dart`**

Add the import (after `import 'ring_screen.dart';`):

```dart
import 'stats_screen.dart';
```

Replace the `case 2:` block in `_activeTab()`:

```dart
      case 2:
        return const _ComingSoon(
            icon: Icons.bedtime_outlined,
            title: 'Sleep',
            body: 'Sleep insights and smart wake windows. Coming soon.');
```

with:

```dart
      case 2:
        return const StatsScreen();
```

Replace the `default:` block (wire `onStreak` to switch to the Stats tab, index 2):

```dart
      default:
        return HomeScreen(
            onNew: _openNew, onEdit: _openEdit, onPreview: _preview);
```

with:

```dart
      default:
        return HomeScreen(
          onNew: _openNew,
          onEdit: _openEdit,
          onPreview: _preview,
          onStreak: () => setState(() => _tab = 2),
        );
```

In `_tabBar()`, replace the Sleep tab item:

```dart
      (icon: Icons.bedtime_outlined, label: 'Sleep'),
```

with:

```dart
      (icon: Icons.insights_outlined, label: 'Stats'),
```

- [ ] **Step 2: Edit `app_shell_test.dart`**

Add these imports (after `import 'package:rise/domain/scheduled_occurrence.dart';`):

```dart
import 'package:rise/domain/wake_event.dart';
import 'package:rise/ui/screens/stats_screen.dart';
```

Add the `wakeEventsProvider` override to `_overrides` (StatsScreen reads it) — replace:

```dart
List<Override> _overrides(List<Alarm> alarms, ScheduledOccurrence? next) => [
      alarmsProvider.overrideWith((ref) => Stream.value(alarms)),
      nextOccurrenceProvider.overrideWith((ref) async => next),
      streakProvider.overrideWithValue(StreakStats.empty),
    ];
```

with:

```dart
List<Override> _overrides(List<Alarm> alarms, ScheduledOccurrence? next) => [
      alarmsProvider.overrideWith((ref) => Stream.value(alarms)),
      nextOccurrenceProvider.overrideWith((ref) async => next),
      streakProvider.overrideWithValue(StreakStats.empty),
      wakeEventsProvider.overrideWith((ref) => Stream.value(const <WakeEvent>[])),
    ];
```

Add these two tests inside `main()`:

```dart
  testWidgets('the Stats tab shows the Stats screen', (t) async {
    await t.pumpWidget(_host(_container()));
    await t.pump();
    await t.tap(find.text('Stats')); // the tab label
    await t.pump();
    expect(find.byType(StatsScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets('tapping the Home streak pill deep-links to the Stats tab', (t) async {
    await t.pumpWidget(_host(_container()));
    await t.pump();
    // On Home the streak is empty, so the pill reads "Start".
    await t.tap(find.text('Start'));
    await t.pump();
    expect(find.byType(StatsScreen), findsOneWidget);
  });
```

- [ ] **Step 3: Run the app-shell tests, whole suite, analyze**

```bash
flutter test test/ui/screens/app_shell_test.dart
flutter test
flutter analyze
```
Expected: app-shell tests (existing + 2 new) green; whole suite green; `No issues found!`.

- [ ] **Step 4: Commit**

```bash
git add lib/ui/screens/app_shell.dart test/ui/screens/app_shell_test.dart
git commit -m "feat(ui): turn the Sleep tab into Stats and deep-link the streak pill"
```

- [ ] **Step 5: On-device verification (run on the physical Samsung)**

Fresh-build install (`flutter build apk --release` then `adb install -r`), then:

1. **New install / fresh data:** first alarm you set and dismiss creates history. Set an alarm ~2 min out, lock the phone, let it ring, and **dismiss on time** (within 15 min). → the Home **streak pill** shows **1**; open **Stats** (tap the pill or the Stats tab) → the streak card shows 1, today's calendar cell is on-time (green), "this week" reads "On time 1 of 1".
2. **A second on-time day** (or simulate by setting/dismissing again the next day) increments the streak.
3. **A miss:** let an alarm ring and **don't dismiss it** (or dismiss well after 15 min) → Stats shows that day as a miss (red cell); the streak resets (or consumes a freeze once you've earned one).
4. **Snooze/wake-check are NOT in this increment** — snoozeCount stays 0 and there's no "still up?" yet (that's Phase 4b). Confirm the ring screen still only offers dismiss (slide/mission), unchanged from Plan 3.
5. Existing Plan-3 behaviors still hold: rings through silent+locked, mission gates dismissal, reboot re-arm.

Record results in `docs/superpowers/reliability/2026-07-17-phase4a-device-results.md`. This is Phase 4a's finish line before merge to `main`.

---

## All Phase 4a tasks specified

Tasks 1–9 now have complete, executable code. After Task 9 executes and the device protocol passes, `phase4a` is ready for the final whole-branch review and merge. **Phase 4b** (snooze budget + wake-up check) is the next increment, building on the wake-event log, `snoozeCount`, and the open-event model established here.

- **Task 4 — WakeEventRepository** (`wake_event_repository.dart`): `openRing({alarmId, scheduledAt, firstRingAt, label}) → Future<int>` (reuse an open event for the alarm within 6 h, else insert); `finalizeDismiss({alarmId, dismissedAt, method}) → Future<void>` (find open event, set `dismissedAt`/`method`/`onTime = dismissedAt−firstRingAt ≤ 15 min`; no-op if none); `watchAll() → Stream<List<WakeEvent>>`. Tests: reuse-window, onTime boundary 14:59/15:01, no-op on closed/missing.
- **Task 5 — WakeRecorder + providers** (`wake_recorder.dart`, `wake_providers.dart`; expose `RiseDatabase` on `AlarmSyncService`): `WakeRecorder(repo, alarmRepo)` with `openRing(int alarmId)` (looks up the alarm → label + `scheduledAt` = today's local h:m→UTC) and `finalizeDismiss(int alarmId, {String? method})`; providers `wakeEventRepositoryProvider`, `wakeRecorderProvider`, `wakeEventsProvider`, `streakProvider = computeStreak(events, DateTime.now())`.
- **Task 6 — Wire recording into the ring flow** (modify `ring_screen.dart` + `main.dart`): add `bool record = false`; when `record`, `initState` opens (`ref.read(wakeRecorderProvider).openRing`) and a successful `_dismiss(method)` finalizes — both wrapped best-effort; `_dismiss` takes the method ('mission' vs 'slide'); `main._showRing` passes `record: true`. Existing ring tests keep passing (default `record: false` → no provider read); a new test with a fake recorder verifies open+finalize.
- **Task 7 — Live Home streak pill** (modify `home_screen.dart`): add `onStreak` callback; the header renders a tappable flame+count pill from `streakProvider` (muted "Start a streak" at 0). Tests: pill shows count; tap calls `onStreak`.
- **Task 8 — Stats screen** (`stats_screen.dart`): consumes `streakProvider` + `wakeEventsProvider`; current/best streak, freezes, on-time calendar (~30-day grid), 7-day wake-vs-set chart (+ snooze count, 0 in 4a), a plain consistency line; empty state. Tests with overridden providers.
- **Task 9 — App shell Sleep→Stats + deep-link + device verify** (modify `app_shell.dart`): rename the Sleep tab to "Stats" hosting `StatsScreen`; wire `HomeScreen.onStreak` → switch to the Stats tab. Tests: Stats tab shows `StatsScreen`; the Home pill deep-links. Then the on-device verification protocol (create alarm → ring → dismiss → streak pill increments; miss → streak reflects it; stats screen populated).
