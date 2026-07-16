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
          // v1 -> v2: dismiss missions. Existing rows keep their data and get
          // the column defaults ('none'/'easy'); no wipe.
          if (from < 2) {
            await m.addColumn(alarms, alarms.mission);
            await m.addColumn(alarms, alarms.missionDiff);
          }
        },
      );
}
