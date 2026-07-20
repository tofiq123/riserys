/// Formats a 24-hour clock time as a 12-hour "h:mm AM/PM" string.
///
/// Pure and locale-agnostic (English AM/PM only for v1 — full localisation is a
/// launch punch-list item). Examples: (7, 5) -> "7:05 AM", (0, 0) -> "12:00 AM",
/// (12, 0) -> "12:00 PM", (13, 30) -> "1:30 PM".
String formatClock(int hour24, int minute) {
  final isAm = hour24 < 12;
  final h = hour24 % 12;
  final h12 = h == 0 ? 12 : h;
  final mm = minute.toString().padLeft(2, '0');
  return '$h12:$mm ${isAm ? 'AM' : 'PM'}';
}
