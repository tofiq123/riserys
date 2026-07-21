import 'package:drift/drift.dart';

import '../../domain/alarm.dart';
import 'database.dart';

/// Reads and writes alarms. Translates between the domain's `Set<int> days`
/// and the database's comma-joined text column.
class AlarmRepository {
  AlarmRepository(this._db);

  final RiseDatabase _db;

  /// The underlying database, so a sibling repository (e.g. WakeEventRepository)
  /// can be built over the SAME handle — two handles to the file would drift.
  RiseDatabase get database => _db;

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
        vibrationPattern: row.vibrationPattern,
        mission: row.mission,
        missionDiff: row.missionDiff,
        missionCount: row.missionCount,
        missionData: row.missionData,
        lastDismissedAt: row.lastDismissedAt,
        snoozedUntil: row.snoozedUntil,
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
      vibrationPattern: Value(alarm.vibrationPattern),
      mission: Value(alarm.mission),
      missionDiff: Value(alarm.missionDiff),
      missionCount: Value(alarm.missionCount),
      missionData: Value(alarm.missionData),
      lastDismissedAt: Value(alarm.lastDismissedAt),
      snoozedUntil: Value(alarm.snoozedUntil),
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

  /// Records that [id] was dismissed at [at]. A one-shot alarm also disables
  /// itself here: an empty day set means "fire once", and without this it
  /// would re-arm for tomorrow forever.
  Future<void> recordDismissed(int id, DateTime at) async {
    final row = await (_db.select(_db.alarms)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return;

    final isOneShot = decodeDays(row.days).isEmpty;
    await (_db.update(_db.alarms)..where((t) => t.id.equals(id))).write(
      AlarmsCompanion(
        lastDismissedAt: Value(at.toUtc()),
        enabled: isOneShot ? const Value(false) : const Value.absent(),
        snoozedUntil: const Value(null),
      ),
    );
  }

  /// Defers the alarm's next firing to [at] (a snooze). Cleared by
  /// [clearSnoozedUntil] or [recordDismissed].
  Future<void> setSnoozedUntil(int id, DateTime at) =>
      (_db.update(_db.alarms)..where((t) => t.id.equals(id)))
          .write(AlarmsCompanion(snoozedUntil: Value(at.toUtc())));

  Future<void> clearSnoozedUntil(int id) =>
      (_db.update(_db.alarms)..where((t) => t.id.equals(id)))
          .write(const AlarmsCompanion(snoozedUntil: Value(null)));
}
