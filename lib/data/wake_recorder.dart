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
