import 'package:timezone/timezone.dart' as tz;

import 'alarm.dart';

/// How many days ahead to search before giving up. A repeating alarm always
/// fires within 7 days; 8 gives one day of slack for same-day rollover.
const int _searchHorizonDays = 8;

/// Maps Dart's weekday numbering (Mon=1 … Sun=7) to the domain's day indices
/// (Sun=0 … Sat=6), matching the design's S M T W T F S chips.
int weekdayToIndex(int dartWeekday) => dartWeekday % 7;

/// Resolves the wall time (`year-month-day hour:minute`) in [location] to a
/// concrete instant.
///
/// During a DST spring-forward gap the requested wall time does not exist. Per
/// spec, we fire at the first valid instant after the gap: we walk forward a
/// minute at a time until a wall time round-trips. Real-world gaps are at most
/// two hours, so the 180-minute cap can never be reached in practice.
tz.TZDateTime resolveWallTime(
  tz.Location location,
  int year,
  int month,
  int day,
  int hour,
  int minute,
) {
  final candidate = tz.TZDateTime(location, year, month, day, hour, minute);
  if (candidate.hour == hour &&
      candidate.minute == minute &&
      candidate.day == day) {
    return candidate;
  }

  for (var add = 1; add <= 180; add++) {
    final total = hour * 60 + minute + add;
    final probeHour = (total ~/ 60) % 24;
    final probeMinute = total % 60;
    final dayShift = total ~/ 1440;
    final date = DateTime.utc(year, month, day).add(Duration(days: dayShift));
    final probe = tz.TZDateTime(
        location, date.year, date.month, date.day, probeHour, probeMinute);
    if (probe.hour == probeHour && probe.minute == probeMinute) {
      return probe;
    }
  }

  // Unreachable for real timezone data; return the library's normalization.
  return candidate;
}

/// The next instant [alarm] should fire, strictly after [from], or null if the
/// alarm is disabled.
///
/// Alarms follow the local wall clock: a 6:30 alarm is 6:30 on both sides of a
/// DST transition. Calendar arithmetic is done in UTC to avoid Duration-based
/// day math silently shifting the wall clock across a transition.
tz.TZDateTime? nextOccurrence({
  required Alarm alarm,
  required tz.TZDateTime from,
  required tz.Location location,
}) {
  if (!alarm.enabled) return null;

  final startDate = DateTime.utc(from.year, from.month, from.day);

  for (var offset = 0; offset <= _searchHorizonDays; offset++) {
    final date = startDate.add(Duration(days: offset));

    if (!alarm.isOneShot) {
      final index = weekdayToIndex(
          DateTime.utc(date.year, date.month, date.day).weekday);
      if (!alarm.days.contains(index)) continue;
    }

    final candidate = resolveWallTime(
        location, date.year, date.month, date.day, alarm.hour, alarm.minute);

    if (candidate.isAfter(from)) return candidate;
  }

  return null;
}
