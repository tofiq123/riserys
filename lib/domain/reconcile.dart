import 'package:timezone/timezone.dart' as tz;

import 'alarm.dart';
import 'schedule_math.dart';
import 'scheduled_occurrence.dart';

/// The work needed to bring the native scheduler in line with [desired].
class ReconcilePlan {
  const ReconcilePlan({required this.toSchedule, required this.toCancel});

  final List<ScheduledOccurrence> toSchedule;
  final List<int> toCancel;

  bool get isEmpty => toSchedule.isEmpty && toCancel.isEmpty;

  @override
  String toString() =>
      'ReconcilePlan(schedule: ${toSchedule.length}, cancel: ${toCancel.length})';
}

/// Every alarm's next firing, sorted soonest-first.
List<ScheduledOccurrence> desiredOccurrences({
  required List<Alarm> alarms,
  required tz.TZDateTime now,
  required tz.Location location,
}) {
  final result = <ScheduledOccurrence>[];

  for (final alarm in alarms) {
    final next = nextOccurrence(alarm: alarm, from: now, location: location);
    if (next == null) continue;
    result.add(ScheduledOccurrence(
      alarmId: alarm.id,
      fireAt: next.toUtc(),
      label: alarm.label,
      soundAsset: alarm.soundAsset,
      vibrate: alarm.vibrate,
    ));
  }

  result.sort((a, b) => a.fireAt.compareTo(b.fireAt));
  return result;
}

/// Diffs desired against currently-scheduled state.
///
/// Scheduling an id that is already scheduled replaces it (Android's
/// PendingIntent.FLAG_UPDATE_CURRENT semantics), so a changed occurrence only
/// needs a schedule, never a paired cancel. Must be idempotent: reconciling an
/// unchanged state produces an empty plan.
ReconcilePlan diffSchedule({
  required List<ScheduledOccurrence> desired,
  required List<ScheduledOccurrence> current,
}) {
  final currentById = {for (final o in current) o.alarmId: o};
  final desiredIds = desired.map((o) => o.alarmId).toSet();

  final toSchedule = <ScheduledOccurrence>[];
  for (final want in desired) {
    final have = currentById[want.alarmId];
    if (have != want) toSchedule.add(want);
  }

  final toCancel = <int>[
    for (final o in current)
      if (!desiredIds.contains(o.alarmId)) o.alarmId
  ];

  return ReconcilePlan(toSchedule: toSchedule, toCancel: toCancel);
}
