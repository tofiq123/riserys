/// Formats a 24-hour clock time as either a 12-hour "h:mm AM/PM" string or a
/// zero-padded 24-hour "HH:mm" string, per the user's [use24h] preference.
///
/// Pure and locale-agnostic (English AM/PM only for v1 — full localisation is a
/// launch punch-list item). Examples (12h): (7, 5) -> "7:05 AM",
/// (0, 0) -> "12:00 AM", (12, 0) -> "12:00 PM", (13, 30) -> "1:30 PM".
/// Examples (24h): (7, 5) -> "07:05", (0, 0) -> "00:00", (13, 30) -> "13:30".
String formatClock(int hour24, int minute, {bool use24h = false}) {
  final mm = minute.toString().padLeft(2, '0');
  if (use24h) {
    // Zero-padded 24-hour clock, no AM/PM — the "digital" format used by most
    // of the world.
    return '${hour24.toString().padLeft(2, '0')}:$mm';
  }
  final isAm = hour24 < 12;
  final h = hour24 % 12;
  final h12 = h == 0 ? 12 : h;
  return '$h12:$mm ${isAm ? 'AM' : 'PM'}';
}

/// The individual pieces of a formatted clock time, for displays that render
/// the hour, minute and period separately (the big ring clock and the home
/// hero, which style the AM/PM label smaller than the digits).
///
/// In 24-hour mode [period] is the empty string (there is no AM/PM label) and
/// [hour] is the zero-padded 0–23 hour; callers should skip rendering the
/// period widget when it's empty. In 12-hour mode [hour] carries no leading
/// zero and [period] is "AM"/"PM".
typedef ClockParts = ({String hour, String minute, String period});

ClockParts formatClockParts(int hour24, int minute, {bool use24h = false}) {
  final mm = minute.toString().padLeft(2, '0');
  if (use24h) {
    return (hour: hour24.toString().padLeft(2, '0'), minute: mm, period: '');
  }
  final isAm = hour24 < 12;
  final h = hour24 % 12;
  final h12 = h == 0 ? 12 : h;
  return (hour: '$h12', minute: mm, period: isAm ? 'AM' : 'PM');
}
