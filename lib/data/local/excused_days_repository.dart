import 'database.dart';

/// Reads and writes the set of "rough night" days the user excused. A day is
/// keyed by its local-midnight instant; excusing a day exempts it from breaking
/// the streak (see [computeStreak]'s `excusedDays`).
class ExcusedDaysRepository {
  ExcusedDaysRepository(this._db);

  final RiseDatabase _db;

  /// Normalises any instant to the local-midnight day it falls in.
  static DateTime dayOf(DateTime t) {
    final l = t.toLocal();
    return DateTime(l.year, l.month, l.day);
  }

  /// Marks [day]'s local day as a rough night. Idempotent — the day is the
  /// primary key, so re-marking simply replaces the row.
  Future<void> excuse(DateTime day) => _db
      .into(_db.excusedDays)
      .insertOnConflictUpdate(ExcusedDaysCompanion.insert(day: dayOf(day)));

  /// Removes [day] from the excused set. No-op if it wasn't marked.
  Future<void> unexcuse(DateTime day) =>
      (_db.delete(_db.excusedDays)..where((t) => t.day.equals(dayOf(day))))
          .go();

  /// The excused days as a set of local-midnight instants, kept live.
  Stream<Set<DateTime>> watchAll() => _db
      .select(_db.excusedDays)
      .watch()
      .map((rows) => rows.map((r) => dayOf(r.day)).toSet());

  Future<Set<DateTime>> all() async {
    final rows = await _db.select(_db.excusedDays).get();
    return rows.map((r) => dayOf(r.day)).toSet();
  }
}
