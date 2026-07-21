import 'clock_format.dart';

const int _minutesPerDay = 1440;

/// The next suggested wake time when nudging [fromHour]:[fromMinute] toward the
/// goal [goalHour]:[goalMinute] by at most [stepMinutes].
///
/// Pure and deterministic. Moves along the *shorter* arc of the 24-hour clock,
/// so it handles both earlier and later goals and wraps across midnight. If the
/// remaining gap is within one step (or already zero) it lands exactly on the
/// goal — it never overshoots. This is only ever a *suggestion*: callers must
/// have the user explicitly apply it. Silently rescheduling an alarm toward an
/// earlier time could cause a missed wake, which is a clinical red line.
///
/// Example: from 08:00 toward 06:00 with a 15-minute step returns 07:45; the
/// next application returns 07:30, and so on, until it reaches 06:00.
({int hour, int minute}) nextShiftedWakeTime({
  required int fromHour,
  required int fromMinute,
  required int goalHour,
  required int goalMinute,
  int stepMinutes = 15,
}) {
  final from = _clampToDay(fromHour * 60 + fromMinute);
  final goal = _clampToDay(goalHour * 60 + goalMinute);
  final step = stepMinutes.abs();

  // Shortest signed delta around the clock, in (-720, 720].
  final delta = ((goal - from + _minutesPerDay ~/ 2) % _minutesPerDay) -
      _minutesPerDay ~/ 2;

  // Move by at most one step toward the goal; clamp lands us exactly on the
  // goal when the remaining gap is within a step.
  final move = delta.clamp(-step, step);
  final next = (from + move) % _minutesPerDay;

  return (hour: next ~/ 60, minute: next % 60);
}

/// Formats [nextShiftedWakeTime]'s result as a clock string, honouring the
/// caller's 12h/24h [use24h] preference.
String formatShift(({int hour, int minute}) t, {bool use24h = false}) =>
    formatClock(t.hour, t.minute, use24h: use24h);

int _clampToDay(int minutes) => ((minutes % _minutesPerDay) + _minutesPerDay) %
    _minutesPerDay;
