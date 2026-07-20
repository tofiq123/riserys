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

  /// UTC instant the alarm was last dismissed, or null if never dismissed.
  /// Used by recovery to avoid re-ringing an occurrence the user already
  /// dealt with, and by [AlarmRepository.recordDismissed] to disable a
  /// one-shot alarm once it has fired.
  DateTimeColumn get lastDismissedAt => dateTime().nullable()();

  /// Dismiss mission and difficulty (added in schema v2).
  TextColumn get mission => text().withDefault(const Constant('none'))();
  TextColumn get missionDiff => text().withDefault(const Constant('easy'))();

  /// How many times the mission must be completed in a row before dismissal —
  /// a mission "chain" (1–3; added in schema v7). Default 1 = unchanged.
  IntColumn get missionCount => integer().withDefault(const Constant(1))();

  /// When set (UTC), the alarm's next firing is this instant instead of its
  /// schedule — a deferred re-ring from a snooze (added in schema v4).
  DateTimeColumn get snoozedUntil => dateTime().nullable()();

  // Alarm's hour/minute range checks are `assert`s, which are stripped in
  // release builds, and rows built from the database (_toDomain) never went
  // through that constructor validation to begin with — an out-of-range
  // value would not crash, it would just silently ring at the wrong time
  // once TZDateTime normalizes it. schemaVersion is still 1 with no
  // installed base, so enforcing this at the actual trust boundary (the
  // database) is a one-line fix today rather than a migration later.
  @override
  List<String> get customConstraints => [
        'CHECK (hour BETWEEN 0 AND 23)',
        'CHECK (minute BETWEEN 0 AND 59)',
      ];
}

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

  /// Reaction-speed alertness score (0–100) from a PVT dismiss mission, or
  /// null when the dismissal wasn't a PVT mission / produced no score (added
  /// in schema v5).
  IntColumn get alertnessScore => integer().nullable()();
}

/// Local calendar days the user marked as a "rough night" (added in schema v6).
/// Each row exempts that day from breaking the streak — see [computeStreak]'s
/// `excusedDays`. The day is stored as its local-midnight instant and is the
/// primary key, so re-marking the same day is idempotent (insert-or-replace).
@DataClassName('ExcusedDayRow')
class ExcusedDays extends Table {
  DateTimeColumn get day => dateTime()();

  @override
  Set<Column> get primaryKey => {day};
}

@DriftDatabase(tables: [Alarms, WakeEvents, ExcusedDays])
class RiseDatabase extends _$RiseDatabase {
  RiseDatabase(super.e);

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          // v1 -> v2: dismiss missions. Idempotent by design: the DB is opened
          // from several isolates in parallel (foreground, ring, headless boot),
          // so two could race this migration on the first launch after upgrade.
          // Checking the existing columns first turns the loser's ALTER from a
          // "duplicate column name" crash into a safe no-op.
          if (from < 2) {
            final existing = await _columnNames('alarms');
            if (!existing.contains('mission')) {
              await m.addColumn(alarms, alarms.mission);
            }
            if (!existing.contains('mission_diff')) {
              await m.addColumn(alarms, alarms.missionDiff);
            }
          }

          // v2 -> v3: the wake_events table. Idempotent like the column
          // migration above — a losing isolate (or a partial prior run) that
          // finds the table already present skips the create rather than
          // crashing on "table wake_events already exists".
          if (from < 3) {
            if (!await _tableExists('wake_events')) {
              await m.createTable(wakeEvents);
            }
          }

          // v3 -> v4: the snoozed_until column. Idempotent like the v1->v2
          // column migration — a losing isolate that finds it present skips the
          // ALTER rather than crashing on "duplicate column name".
          if (from < 4) {
            final existing = await _columnNames('alarms');
            if (!existing.contains('snoozed_until')) {
              await m.addColumn(alarms, alarms.snoozedUntil);
            }
          }

          // v4 -> v5: the alertness_score column on wake_events. Idempotent
          // like the other add-column migrations — a losing isolate (or a
          // partial prior run) that finds it present skips the ALTER rather
          // than crashing on "duplicate column name". Existing rows keep null.
          if (from < 5) {
            final existing = await _columnNames('wake_events');
            if (!existing.contains('alertness_score')) {
              await m.addColumn(wakeEvents, wakeEvents.alertnessScore);
            }
          }

          // v5 -> v6: the excused_days table (rough-night streak exemption).
          // Idempotent like the v2->v3 table create — a losing isolate (or a
          // partial prior run) that finds it present skips the create rather
          // than crashing on "table excused_days already exists".
          if (from < 6) {
            if (!await _tableExists('excused_days')) {
              await m.createTable(excusedDays);
            }
          }

          // v6 -> v7: the mission_count column on alarms (mission chains).
          // Idempotent like the other add-column migrations — a losing isolate
          // (or a partial prior run) that finds it present skips the ALTER
          // rather than crashing on "duplicate column name". Existing rows keep
          // the default of 1 (a single completion — unchanged behavior).
          if (from < 7) {
            final existing = await _columnNames('alarms');
            if (!existing.contains('mission_count')) {
              await m.addColumn(alarms, alarms.missionCount);
            }
          }
        },
      );

  /// The column names currently on [table], read from sqlite's schema. Used to
  /// make migrations idempotent under the app's multi-isolate DB opens.
  Future<Set<String>> _columnNames(String table) async {
    final rows = await customSelect('PRAGMA table_info($table)').get();
    return rows.map((r) => r.read<String>('name')).toSet();
  }

  /// Whether [table] exists, read from sqlite's own schema. Keeps the v3
  /// table-create migration idempotent under the app's multi-isolate DB opens.
  Future<bool> _tableExists(String table) async {
    final rows = await customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name = ?",
      variables: [Variable<String>(table)],
    ).get();
    return rows.isNotEmpty;
  }
}
