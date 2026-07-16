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

@DriftDatabase(tables: [Alarms])
class RiseDatabase extends _$RiseDatabase {
  RiseDatabase(super.e);

  @override
  int get schemaVersion => 2;

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
        },
      );

  /// The column names currently on [table], read from sqlite's schema. Used to
  /// make migrations idempotent under the app's multi-isolate DB opens.
  Future<Set<String>> _columnNames(String table) async {
    final rows = await customSelect('PRAGMA table_info($table)').get();
    return rows.map((r) => r.read<String>('name')).toSet();
  }
}
