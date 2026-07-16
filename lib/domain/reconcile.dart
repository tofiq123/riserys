import 'package:timezone/timezone.dart' as tz;

import 'alarm.dart';
import 'schedule_math.dart';
import 'scheduled_occurrence.dart';

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

  // Secondary key on alarmId: Dart's List.sort is not stable, so without a
  // tie-breaker, two alarms firing at the exact same instant would order
  // nondeterministically from one reconcile to the next.
  result.sort((a, b) {
    final byFireAt = a.fireAt.compareTo(b.fireAt);
    return byFireAt != 0 ? byFireAt : a.alarmId.compareTo(b.alarmId);
  });
  return result;
}
