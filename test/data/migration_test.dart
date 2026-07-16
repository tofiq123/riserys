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
    expect(db.schemaVersion, 2);
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
}
