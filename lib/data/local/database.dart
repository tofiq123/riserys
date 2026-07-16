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
}

@DriftDatabase(tables: [Alarms])
class RiseDatabase extends _$RiseDatabase {
  RiseDatabase(super.e);

  @override
  int get schemaVersion => 1;
}
