import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/local/database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('upgrading a v1 database adds mission columns and keeps existing rows', () async {
    // Build a schema-v1 alarms table by hand (no mission columns), as it
    // exists on an already-installed device, and seed one alarm.
    final raw = sqlite3.openInMemory();
    raw.execute('''
      CREATE TABLE alarms (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        hour INTEGER NOT NULL,
        minute INTEGER NOT NULL,
        days TEXT NOT NULL DEFAULT '',
        enabled INTEGER NOT NULL DEFAULT 1,
        label TEXT NOT NULL DEFAULT 'Alarm',
        sound_asset TEXT NOT NULL DEFAULT 'sounds/default_alarm.mp3',
        vibrate INTEGER NOT NULL DEFAULT 1,
        last_dismissed_at INTEGER,
        CHECK (hour BETWEEN 0 AND 23),
        CHECK (minute BETWEEN 0 AND 59)
      );
    ''');
    raw.execute("INSERT INTO alarms (hour, minute, label) VALUES (6, 30, 'Run');");
    raw.execute('PRAGMA user_version = 1;');

    // Opening RiseDatabase over this connection triggers onUpgrade(1 -> 2).
    final db = RiseDatabase(NativeDatabase.opened(raw));
    addTearDown(db.close);

    final rows = await db.select(db.alarms).get();
    expect(rows, hasLength(1), reason: 'existing row survives the upgrade');
    expect(rows.single.label, 'Run');
    expect(rows.single.mission, 'none', reason: 'new column defaults');
    expect(rows.single.missionDiff, 'easy');
    // schemaVersion is a synchronous getter (not a Future); await on it here
    // would be a no-op that only trips the await_only_futures lint.
    expect(db.schemaVersion, 9);
  });

  test('upgrading is idempotent when the new columns already exist', () async {
    // Simulates the isolate that loses the migration race (or a partial
    // prior migration): the alarms table is already v1-shaped plus the v2
    // columns, but user_version still says 1, so onUpgrade(1 -> 2) runs.
    final raw = sqlite3.openInMemory();
    raw.execute('''
      CREATE TABLE alarms (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        hour INTEGER NOT NULL,
        minute INTEGER NOT NULL,
        days TEXT NOT NULL DEFAULT '',
        enabled INTEGER NOT NULL DEFAULT 1,
        label TEXT NOT NULL DEFAULT 'Alarm',
        sound_asset TEXT NOT NULL DEFAULT 'sounds/default_alarm.mp3',
        vibrate INTEGER NOT NULL DEFAULT 1,
        last_dismissed_at INTEGER,
        mission TEXT NOT NULL DEFAULT 'none',
        mission_diff TEXT NOT NULL DEFAULT 'easy',
        CHECK (hour BETWEEN 0 AND 23),
        CHECK (minute BETWEEN 0 AND 59)
      );
    ''');
    raw.execute("INSERT INTO alarms (hour, minute, label) VALUES (7, 0, 'Kept');");
    raw.execute('PRAGMA user_version = 1;');

    final db = RiseDatabase(NativeDatabase.opened(raw));
    addTearDown(db.close);

    // Must not throw "duplicate column name"; row and columns intact.
    final rows = await db.select(db.alarms).get();
    expect(rows, hasLength(1));
    expect(rows.single.label, 'Kept');
    expect(rows.single.mission, 'none');
  });

  test('a fresh database is created at v2 with the mission columns', () async {
    final db = RiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final id = await db.into(db.alarms).insert(
        AlarmsCompanion.insert(hour: 6, minute: 30));
    final row = await (db.select(db.alarms)..where((t) => t.id.equals(id))).getSingle();
    expect(row.mission, 'none');
    expect(row.missionDiff, 'easy');
  });

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
    expect(db.schemaVersion, 9);
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

  test('upgrading a v3 database adds snoozed_until and keeps existing alarms', () async {
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
    raw.execute('''
      CREATE TABLE wake_events (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        alarm_id INTEGER NOT NULL, scheduled_at INTEGER NOT NULL,
        first_ring_at INTEGER NOT NULL, dismissed_at INTEGER, method TEXT,
        snooze_count INTEGER NOT NULL DEFAULT 0, mission_failures INTEGER NOT NULL DEFAULT 0,
        on_time INTEGER NOT NULL DEFAULT 0, label TEXT NOT NULL DEFAULT 'Alarm'
      );
    ''');
    raw.execute("INSERT INTO alarms (hour, minute, label) VALUES (6, 30, 'Run');");
    raw.execute('PRAGMA user_version = 3;');

    final db = RiseDatabase(NativeDatabase.opened(raw));
    addTearDown(db.close);

    final alarms = await db.select(db.alarms).get();
    expect(alarms.single.label, 'Run', reason: 'alarms survive the upgrade');
    expect(alarms.single.snoozedUntil, isNull, reason: 'new column defaults null');
    expect(db.schemaVersion, 9);
  });

  test('upgrading to v4 is idempotent when snoozed_until already exists', () async {
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
        snoozed_until INTEGER,
        CHECK (hour BETWEEN 0 AND 23), CHECK (minute BETWEEN 0 AND 59)
      );
    ''');
    // A real v3 DB also has wake_events (created at the v2->v3 migration).
    raw.execute('''
      CREATE TABLE wake_events (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        alarm_id INTEGER NOT NULL, scheduled_at INTEGER NOT NULL,
        first_ring_at INTEGER NOT NULL, dismissed_at INTEGER, method TEXT,
        snooze_count INTEGER NOT NULL DEFAULT 0, mission_failures INTEGER NOT NULL DEFAULT 0,
        on_time INTEGER NOT NULL DEFAULT 0, label TEXT NOT NULL DEFAULT 'Alarm'
      );
    ''');
    raw.execute("INSERT INTO alarms (hour, minute, label) VALUES (7, 0, 'Kept');");
    raw.execute('PRAGMA user_version = 3;');

    final db = RiseDatabase(NativeDatabase.opened(raw));
    addTearDown(db.close);

    // Must not throw "duplicate column name snoozed_until".
    final rows = await db.select(db.alarms).get();
    expect(rows.single.label, 'Kept');
  });

  test('a fresh database is created at v4 with snoozed_until', () async {
    final db = RiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final id = await db.into(db.alarms).insert(AlarmsCompanion.insert(
      hour: 6,
      minute: 30,
      snoozedUntil: Value(DateTime.utc(2026, 7, 20, 6, 39)),
    ));
    final row = await (db.select(db.alarms)..where((t) => t.id.equals(id))).getSingle();
    expect(row.snoozedUntil, isNotNull);
  });

  test('upgrading a v4 database adds alertness_score and keeps existing events',
      () async {
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
        snoozed_until INTEGER,
        CHECK (hour BETWEEN 0 AND 23), CHECK (minute BETWEEN 0 AND 59)
      );
    ''');
    // A v4 wake_events table: no alertness_score column yet.
    raw.execute('''
      CREATE TABLE wake_events (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        alarm_id INTEGER NOT NULL, scheduled_at INTEGER NOT NULL,
        first_ring_at INTEGER NOT NULL, dismissed_at INTEGER, method TEXT,
        snooze_count INTEGER NOT NULL DEFAULT 0, mission_failures INTEGER NOT NULL DEFAULT 0,
        on_time INTEGER NOT NULL DEFAULT 0, label TEXT NOT NULL DEFAULT 'Alarm'
      );
    ''');
    raw.execute(
        "INSERT INTO wake_events (alarm_id, scheduled_at, first_ring_at, label) VALUES (7, 0, 0, 'Kept');");
    raw.execute('PRAGMA user_version = 4;');

    final db = RiseDatabase(NativeDatabase.opened(raw));
    addTearDown(db.close);

    final ev = await db.select(db.wakeEvents).getSingle();
    expect(ev.label, 'Kept', reason: 'existing event survives the upgrade');
    expect(ev.alertnessScore, isNull, reason: 'new column defaults null');
    expect(db.schemaVersion, 9);
  });

  test('upgrading to v5 is idempotent when alertness_score already exists', () async {
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
        snoozed_until INTEGER,
        CHECK (hour BETWEEN 0 AND 23), CHECK (minute BETWEEN 0 AND 59)
      );
    ''');
    // wake_events already has alertness_score (a losing isolate / partial prior
    // run), but user_version still says 4, so onUpgrade(4 -> 5) will run.
    raw.execute('''
      CREATE TABLE wake_events (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        alarm_id INTEGER NOT NULL, scheduled_at INTEGER NOT NULL,
        first_ring_at INTEGER NOT NULL, dismissed_at INTEGER, method TEXT,
        snooze_count INTEGER NOT NULL DEFAULT 0, mission_failures INTEGER NOT NULL DEFAULT 0,
        on_time INTEGER NOT NULL DEFAULT 0, label TEXT NOT NULL DEFAULT 'Alarm',
        alertness_score INTEGER
      );
    ''');
    raw.execute(
        "INSERT INTO wake_events (alarm_id, scheduled_at, first_ring_at, alertness_score) VALUES (5, 0, 0, 72);");
    raw.execute('PRAGMA user_version = 4;');

    final db = RiseDatabase(NativeDatabase.opened(raw));
    addTearDown(db.close);

    // Must not throw "duplicate column name alertness_score"; the row is intact.
    final ev = await db.select(db.wakeEvents).getSingle();
    expect(ev.alarmId, 5);
    expect(ev.alertnessScore, 72);
  });

  test('a fresh database is created at v5 with alertness_score', () async {
    final db = RiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final id = await db.into(db.wakeEvents).insert(WakeEventsCompanion.insert(
      alarmId: 3,
      scheduledAt: DateTime.utc(2026, 7, 20, 6),
      firstRingAt: DateTime.utc(2026, 7, 20, 6),
      alertnessScore: const Value(91),
    ));
    final ev = await (db.select(db.wakeEvents)..where((t) => t.id.equals(id))).getSingle();
    expect(ev.alertnessScore, 91);
  });

  test('upgrading a v5 database adds excused_days and keeps existing rows',
      () async {
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
        snoozed_until INTEGER,
        CHECK (hour BETWEEN 0 AND 23), CHECK (minute BETWEEN 0 AND 59)
      );
    ''');
    raw.execute('''
      CREATE TABLE wake_events (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        alarm_id INTEGER NOT NULL, scheduled_at INTEGER NOT NULL,
        first_ring_at INTEGER NOT NULL, dismissed_at INTEGER, method TEXT,
        snooze_count INTEGER NOT NULL DEFAULT 0, mission_failures INTEGER NOT NULL DEFAULT 0,
        on_time INTEGER NOT NULL DEFAULT 0, label TEXT NOT NULL DEFAULT 'Alarm',
        alertness_score INTEGER
      );
    ''');
    raw.execute("INSERT INTO alarms (hour, minute, label) VALUES (6, 30, 'Run');");
    raw.execute('PRAGMA user_version = 5;');

    final db = RiseDatabase(NativeDatabase.opened(raw));
    addTearDown(db.close);

    final alarms = await db.select(db.alarms).get();
    expect(alarms.single.label, 'Run', reason: 'alarms survive the upgrade');
    // The new table is usable after the upgrade.
    final day = DateTime(2026, 7, 18);
    await db.into(db.excusedDays).insert(ExcusedDaysCompanion.insert(day: day));
    final rows = await db.select(db.excusedDays).get();
    expect(rows.single.day, day);
    expect(db.schemaVersion, 9);
  });

  test('upgrading to v6 is idempotent when excused_days already exists', () async {
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
        snoozed_until INTEGER,
        CHECK (hour BETWEEN 0 AND 23), CHECK (minute BETWEEN 0 AND 59)
      );
    ''');
    raw.execute('''
      CREATE TABLE wake_events (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        alarm_id INTEGER NOT NULL, scheduled_at INTEGER NOT NULL,
        first_ring_at INTEGER NOT NULL, dismissed_at INTEGER, method TEXT,
        snooze_count INTEGER NOT NULL DEFAULT 0, mission_failures INTEGER NOT NULL DEFAULT 0,
        on_time INTEGER NOT NULL DEFAULT 0, label TEXT NOT NULL DEFAULT 'Alarm',
        alertness_score INTEGER
      );
    ''');
    // excused_days already present (a losing isolate / partial prior run), but
    // user_version still says 5, so onUpgrade(5 -> 6) will run.
    raw.execute('''
      CREATE TABLE excused_days (
        day INTEGER NOT NULL PRIMARY KEY
      );
    ''');
    raw.execute('INSERT INTO excused_days (day) VALUES (1000);');
    raw.execute('PRAGMA user_version = 5;');

    final db = RiseDatabase(NativeDatabase.opened(raw));
    addTearDown(db.close);

    // Must not throw "table excused_days already exists"; the row is intact.
    final rows = await db.select(db.excusedDays).get();
    expect(rows, hasLength(1));
  });

  test('a fresh database is created at v6 with excused_days', () async {
    final db = RiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final day = DateTime(2026, 7, 19);
    await db
        .into(db.excusedDays)
        .insert(ExcusedDaysCompanion.insert(day: day));
    final rows = await db.select(db.excusedDays).get();
    expect(rows.single.day, day);
    expect(db.schemaVersion, 9);
  });

  test('upgrading a v6 database adds mission_count and keeps existing alarms',
      () async {
    final raw = sqlite3.openInMemory();
    // A v6 alarms table: mission/mission_diff present, but no mission_count.
    raw.execute('''
      CREATE TABLE alarms (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        hour INTEGER NOT NULL, minute INTEGER NOT NULL,
        days TEXT NOT NULL DEFAULT '', enabled INTEGER NOT NULL DEFAULT 1,
        label TEXT NOT NULL DEFAULT 'Alarm',
        sound_asset TEXT NOT NULL DEFAULT 'sounds/default_alarm.mp3',
        vibrate INTEGER NOT NULL DEFAULT 1, last_dismissed_at INTEGER,
        mission TEXT NOT NULL DEFAULT 'none', mission_diff TEXT NOT NULL DEFAULT 'easy',
        snoozed_until INTEGER,
        CHECK (hour BETWEEN 0 AND 23), CHECK (minute BETWEEN 0 AND 59)
      );
    ''');
    raw.execute('''
      CREATE TABLE wake_events (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        alarm_id INTEGER NOT NULL, scheduled_at INTEGER NOT NULL,
        first_ring_at INTEGER NOT NULL, dismissed_at INTEGER, method TEXT,
        snooze_count INTEGER NOT NULL DEFAULT 0, mission_failures INTEGER NOT NULL DEFAULT 0,
        on_time INTEGER NOT NULL DEFAULT 0, label TEXT NOT NULL DEFAULT 'Alarm',
        alertness_score INTEGER
      );
    ''');
    raw.execute('CREATE TABLE excused_days (day INTEGER NOT NULL PRIMARY KEY);');
    raw.execute("INSERT INTO alarms (hour, minute, label) VALUES (6, 30, 'Run');");
    raw.execute('PRAGMA user_version = 6;');

    final db = RiseDatabase(NativeDatabase.opened(raw));
    addTearDown(db.close);

    final alarms = await db.select(db.alarms).get();
    expect(alarms.single.label, 'Run', reason: 'alarms survive the upgrade');
    expect(alarms.single.missionCount, 1, reason: 'new column defaults to 1');
    expect(db.schemaVersion, 9);
  });

  test('upgrading to v7 is idempotent when mission_count already exists',
      () async {
    final raw = sqlite3.openInMemory();
    // mission_count already present (a losing isolate / partial prior run), but
    // user_version still says 6, so onUpgrade(6 -> 7) will run.
    raw.execute('''
      CREATE TABLE alarms (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        hour INTEGER NOT NULL, minute INTEGER NOT NULL,
        days TEXT NOT NULL DEFAULT '', enabled INTEGER NOT NULL DEFAULT 1,
        label TEXT NOT NULL DEFAULT 'Alarm',
        sound_asset TEXT NOT NULL DEFAULT 'sounds/default_alarm.mp3',
        vibrate INTEGER NOT NULL DEFAULT 1, last_dismissed_at INTEGER,
        mission TEXT NOT NULL DEFAULT 'none', mission_diff TEXT NOT NULL DEFAULT 'easy',
        snoozed_until INTEGER, mission_count INTEGER NOT NULL DEFAULT 1,
        CHECK (hour BETWEEN 0 AND 23), CHECK (minute BETWEEN 0 AND 59)
      );
    ''');
    raw.execute("INSERT INTO alarms (hour, minute, label, mission_count) VALUES (7, 0, 'Kept', 3);");
    raw.execute('PRAGMA user_version = 6;');

    final db = RiseDatabase(NativeDatabase.opened(raw));
    addTearDown(db.close);

    // Must not throw "duplicate column name mission_count"; the row is intact.
    final rows = await db.select(db.alarms).get();
    expect(rows.single.label, 'Kept');
    expect(rows.single.missionCount, 3);
  });

  test('a fresh database is created at v7 with mission_count', () async {
    final db = RiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final id = await db.into(db.alarms).insert(
        AlarmsCompanion.insert(hour: 6, minute: 30, missionCount: const Value(2)));
    final row = await (db.select(db.alarms)..where((t) => t.id.equals(id))).getSingle();
    expect(row.missionCount, 2);
    expect(db.schemaVersion, 9);
  });

  test('upgrading a v7 database adds mission_data and keeps existing alarms',
      () async {
    final raw = sqlite3.openInMemory();
    // A v7 alarms table: mission_count present, but no mission_data.
    raw.execute('''
      CREATE TABLE alarms (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        hour INTEGER NOT NULL, minute INTEGER NOT NULL,
        days TEXT NOT NULL DEFAULT '', enabled INTEGER NOT NULL DEFAULT 1,
        label TEXT NOT NULL DEFAULT 'Alarm',
        sound_asset TEXT NOT NULL DEFAULT 'sounds/default_alarm.mp3',
        vibrate INTEGER NOT NULL DEFAULT 1, last_dismissed_at INTEGER,
        mission TEXT NOT NULL DEFAULT 'none', mission_diff TEXT NOT NULL DEFAULT 'easy',
        snoozed_until INTEGER, mission_count INTEGER NOT NULL DEFAULT 1,
        CHECK (hour BETWEEN 0 AND 23), CHECK (minute BETWEEN 0 AND 59)
      );
    ''');
    raw.execute('''
      CREATE TABLE wake_events (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        alarm_id INTEGER NOT NULL, scheduled_at INTEGER NOT NULL,
        first_ring_at INTEGER NOT NULL, dismissed_at INTEGER, method TEXT,
        snooze_count INTEGER NOT NULL DEFAULT 0, mission_failures INTEGER NOT NULL DEFAULT 0,
        on_time INTEGER NOT NULL DEFAULT 0, label TEXT NOT NULL DEFAULT 'Alarm',
        alertness_score INTEGER
      );
    ''');
    raw.execute('CREATE TABLE excused_days (day INTEGER NOT NULL PRIMARY KEY);');
    raw.execute("INSERT INTO alarms (hour, minute, label) VALUES (6, 30, 'Run');");
    raw.execute('PRAGMA user_version = 7;');

    final db = RiseDatabase(NativeDatabase.opened(raw));
    addTearDown(db.close);

    final alarms = await db.select(db.alarms).get();
    expect(alarms.single.label, 'Run', reason: 'alarms survive the upgrade');
    expect(alarms.single.missionData, isNull, reason: 'new column defaults null');
    expect(db.schemaVersion, 9);
  });

  test('upgrading to v8 is idempotent when mission_data already exists',
      () async {
    final raw = sqlite3.openInMemory();
    // mission_data already present (a losing isolate / partial prior run), but
    // user_version still says 7, so onUpgrade(7 -> 8) will run.
    raw.execute('''
      CREATE TABLE alarms (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        hour INTEGER NOT NULL, minute INTEGER NOT NULL,
        days TEXT NOT NULL DEFAULT '', enabled INTEGER NOT NULL DEFAULT 1,
        label TEXT NOT NULL DEFAULT 'Alarm',
        sound_asset TEXT NOT NULL DEFAULT 'sounds/default_alarm.mp3',
        vibrate INTEGER NOT NULL DEFAULT 1, last_dismissed_at INTEGER,
        mission TEXT NOT NULL DEFAULT 'none', mission_diff TEXT NOT NULL DEFAULT 'easy',
        snoozed_until INTEGER, mission_count INTEGER NOT NULL DEFAULT 1,
        mission_data TEXT,
        CHECK (hour BETWEEN 0 AND 23), CHECK (minute BETWEEN 0 AND 59)
      );
    ''');
    raw.execute(
        "INSERT INTO alarms (hour, minute, label, mission, mission_data) VALUES (7, 0, 'Kept', 'qr', 'RISE-123');");
    raw.execute('PRAGMA user_version = 7;');

    final db = RiseDatabase(NativeDatabase.opened(raw));
    addTearDown(db.close);

    // Must not throw "duplicate column name mission_data"; the row is intact.
    final rows = await db.select(db.alarms).get();
    expect(rows.single.label, 'Kept');
    expect(rows.single.missionData, 'RISE-123');
  });

  test('a fresh database is created at v8 with mission_data', () async {
    final db = RiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final id = await db.into(db.alarms).insert(AlarmsCompanion.insert(
        hour: 6, minute: 30, missionData: const Value('RISE-QR-payload')));
    final row = await (db.select(db.alarms)..where((t) => t.id.equals(id))).getSingle();
    expect(row.missionData, 'RISE-QR-payload');
    expect(db.schemaVersion, 9);
  });

  test('upgrading a v8 database adds vibration_pattern and keeps existing alarms',
      () async {
    final raw = sqlite3.openInMemory();
    // A v8 alarms table: mission_data present, but no vibration_pattern.
    raw.execute('''
      CREATE TABLE alarms (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        hour INTEGER NOT NULL, minute INTEGER NOT NULL,
        days TEXT NOT NULL DEFAULT '', enabled INTEGER NOT NULL DEFAULT 1,
        label TEXT NOT NULL DEFAULT 'Alarm',
        sound_asset TEXT NOT NULL DEFAULT 'sounds/default_alarm.mp3',
        vibrate INTEGER NOT NULL DEFAULT 1, last_dismissed_at INTEGER,
        mission TEXT NOT NULL DEFAULT 'none', mission_diff TEXT NOT NULL DEFAULT 'easy',
        snoozed_until INTEGER, mission_count INTEGER NOT NULL DEFAULT 1,
        mission_data TEXT,
        CHECK (hour BETWEEN 0 AND 23), CHECK (minute BETWEEN 0 AND 59)
      );
    ''');
    raw.execute('''
      CREATE TABLE wake_events (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        alarm_id INTEGER NOT NULL, scheduled_at INTEGER NOT NULL,
        first_ring_at INTEGER NOT NULL, dismissed_at INTEGER, method TEXT,
        snooze_count INTEGER NOT NULL DEFAULT 0, mission_failures INTEGER NOT NULL DEFAULT 0,
        on_time INTEGER NOT NULL DEFAULT 0, label TEXT NOT NULL DEFAULT 'Alarm',
        alertness_score INTEGER
      );
    ''');
    raw.execute('CREATE TABLE excused_days (day INTEGER NOT NULL PRIMARY KEY);');
    raw.execute("INSERT INTO alarms (hour, minute, label) VALUES (6, 30, 'Run');");
    raw.execute('PRAGMA user_version = 8;');

    final db = RiseDatabase(NativeDatabase.opened(raw));
    addTearDown(db.close);

    final alarms = await db.select(db.alarms).get();
    expect(alarms.single.label, 'Run', reason: 'alarms survive the upgrade');
    expect(alarms.single.vibrationPattern, 'standard',
        reason: "new column defaults to 'standard' — today's pattern");
    expect(db.schemaVersion, 9);
  });

  test('upgrading to v9 is idempotent when vibration_pattern already exists',
      () async {
    final raw = sqlite3.openInMemory();
    // vibration_pattern already present (a losing isolate / partial prior
    // run), but user_version still says 8, so onUpgrade(8 -> 9) will run.
    raw.execute('''
      CREATE TABLE alarms (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        hour INTEGER NOT NULL, minute INTEGER NOT NULL,
        days TEXT NOT NULL DEFAULT '', enabled INTEGER NOT NULL DEFAULT 1,
        label TEXT NOT NULL DEFAULT 'Alarm',
        sound_asset TEXT NOT NULL DEFAULT 'sounds/default_alarm.mp3',
        vibrate INTEGER NOT NULL DEFAULT 1, last_dismissed_at INTEGER,
        mission TEXT NOT NULL DEFAULT 'none', mission_diff TEXT NOT NULL DEFAULT 'easy',
        snoozed_until INTEGER, mission_count INTEGER NOT NULL DEFAULT 1,
        mission_data TEXT, vibration_pattern TEXT NOT NULL DEFAULT 'standard',
        CHECK (hour BETWEEN 0 AND 23), CHECK (minute BETWEEN 0 AND 59)
      );
    ''');
    raw.execute(
        "INSERT INTO alarms (hour, minute, label, vibration_pattern) VALUES (7, 0, 'Kept', 'intense');");
    raw.execute('PRAGMA user_version = 8;');

    final db = RiseDatabase(NativeDatabase.opened(raw));
    addTearDown(db.close);

    // Must not throw "duplicate column name vibration_pattern"; row intact.
    final rows = await db.select(db.alarms).get();
    expect(rows.single.label, 'Kept');
    expect(rows.single.vibrationPattern, 'intense');
  });

  test('a fresh database is created at v9 with vibration_pattern', () async {
    final db = RiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final id = await db.into(db.alarms).insert(AlarmsCompanion.insert(
        hour: 6, minute: 30, vibrationPattern: const Value('gentle')));
    final row = await (db.select(db.alarms)..where((t) => t.id.equals(id))).getSingle();
    expect(row.vibrationPattern, 'gentle');
    // And the default is 'standard' when unspecified.
    final id2 = await db.into(db.alarms).insert(
        AlarmsCompanion.insert(hour: 7, minute: 0));
    final row2 =
        await (db.select(db.alarms)..where((t) => t.id.equals(id2))).getSingle();
    expect(row2.vibrationPattern, 'standard');
    expect(db.schemaVersion, 9);
  });
}
