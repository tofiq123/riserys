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
        alertnessScore: r.alertnessScore,
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
  /// [alertnessScore] is the PVT alertness score (0–100) for a PVT dismissal,
  /// or null for any other dismissal.
  Future<void> finalizeDismiss({
    required int alarmId,
    required DateTime dismissedAt,
    String? method,
    int? alertnessScore,
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
        alertnessScore: Value(alertnessScore),
      ),
    );
  }

  /// Increments the open event's snooze count (called when the user snoozes).
  /// No-op if none is open.
  Future<void> bumpSnooze(int alarmId) async {
    final open = await _openRowFor(alarmId);
    if (open == null) return;
    await (_db.update(_db.wakeEvents)..where((t) => t.id.equals(open.id)))
        .write(WakeEventsCompanion(snoozeCount: Value(open.snoozeCount + 1)));
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
