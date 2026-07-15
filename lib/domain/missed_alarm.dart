import 'scheduled_occurrence.dart';

/// Default recovery window from the spec: an alarm due within the last 30
/// minutes and never dismissed should ring now rather than be silently lost.
const Duration kMissedAlarmWindow = Duration(minutes: 30);

/// The most recent occurrence that came due within [window] before [now].
///
/// Used after boot, app update, or a clock change: the device may have been
/// off or the scheduler cleared when the alarm was supposed to ring.
ScheduledOccurrence? findMissedAlarm({
  required List<ScheduledOccurrence> occurrences,
  required DateTime now,
  Duration window = kMissedAlarmWindow,
}) {
  final cutoff = now.subtract(window);

  ScheduledOccurrence? best;
  for (final o in occurrences) {
    final due = !o.fireAt.isAfter(now);
    final fresh = !o.fireAt.isBefore(cutoff);
    if (due && fresh) {
      if (best == null || o.fireAt.isAfter(best.fireAt)) best = o;
    }
  }
  return best;
}
