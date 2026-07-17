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

## Remaining tasks (Tasks 6–9 — full code written just before each is executed)

Each gets its complete code just before dispatch (same flow used for Plan 3). Summary + interfaces:

- **Task 4 — WakeEventRepository** (`wake_event_repository.dart`): `openRing({alarmId, scheduledAt, firstRingAt, label}) → Future<int>` (reuse an open event for the alarm within 6 h, else insert); `finalizeDismiss({alarmId, dismissedAt, method}) → Future<void>` (find open event, set `dismissedAt`/`method`/`onTime = dismissedAt−firstRingAt ≤ 15 min`; no-op if none); `watchAll() → Stream<List<WakeEvent>>`. Tests: reuse-window, onTime boundary 14:59/15:01, no-op on closed/missing.
- **Task 5 — WakeRecorder + providers** (`wake_recorder.dart`, `wake_providers.dart`; expose `RiseDatabase` on `AlarmSyncService`): `WakeRecorder(repo, alarmRepo)` with `openRing(int alarmId)` (looks up the alarm → label + `scheduledAt` = today's local h:m→UTC) and `finalizeDismiss(int alarmId, {String? method})`; providers `wakeEventRepositoryProvider`, `wakeRecorderProvider`, `wakeEventsProvider`, `streakProvider = computeStreak(events, DateTime.now())`.
- **Task 6 — Wire recording into the ring flow** (modify `ring_screen.dart` + `main.dart`): add `bool record = false`; when `record`, `initState` opens (`ref.read(wakeRecorderProvider).openRing`) and a successful `_dismiss(method)` finalizes — both wrapped best-effort; `_dismiss` takes the method ('mission' vs 'slide'); `main._showRing` passes `record: true`. Existing ring tests keep passing (default `record: false` → no provider read); a new test with a fake recorder verifies open+finalize.
- **Task 7 — Live Home streak pill** (modify `home_screen.dart`): add `onStreak` callback; the header renders a tappable flame+count pill from `streakProvider` (muted "Start a streak" at 0). Tests: pill shows count; tap calls `onStreak`.
- **Task 8 — Stats screen** (`stats_screen.dart`): consumes `streakProvider` + `wakeEventsProvider`; current/best streak, freezes, on-time calendar (~30-day grid), 7-day wake-vs-set chart (+ snooze count, 0 in 4a), a plain consistency line; empty state. Tests with overridden providers.
- **Task 9 — App shell Sleep→Stats + deep-link + device verify** (modify `app_shell.dart`): rename the Sleep tab to "Stats" hosting `StatsScreen`; wire `HomeScreen.onStreak` → switch to the Stats tab. Tests: Stats tab shows `StatsScreen`; the Home pill deep-links. Then the on-device verification protocol (create alarm → ring → dismiss → streak pill increments; miss → streak reflects it; stats screen populated).
