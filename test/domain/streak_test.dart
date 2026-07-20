import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/streak.dart';
import 'package:rise/domain/wake_event.dart';

void main() {
  DateTime d(int day) => DateTime(2026, 7, day); // local July 2026 midnights
  final now = DateTime(2026, 7, 20, 12); // "today" = July 20

  // A local event on the given day; on-time (dismissed +3m), late-miss (+30m),
  // or open (never dismissed).
  WakeEvent ev(int day, {required bool onTime, bool open = false}) {
    final ring = DateTime(2026, 7, day, 6);
    return WakeEvent(
      id: 0,
      alarmId: 1,
      scheduledAt: ring,
      firstRingAt: ring,
      dismissedAt: open ? null : ring.add(Duration(minutes: onTime ? 3 : 30)),
      onTime: onTime,
    );
  }

  test('empty log is all zero', () {
    final s = computeStreak([], now);
    expect(s.current, 0);
    expect(s.best, 0);
    expect(s.freezesRemaining, 0);
    expect(s.byDay, isEmpty);
  });

  test('consecutive on-time days build the streak', () {
    final s = computeStreak(
        [ev(17, onTime: true), ev(18, onTime: true), ev(19, onTime: true)], now);
    expect(s.current, 3);
    expect(s.best, 3);
    expect(s.byDay[d(18)], DayOutcome.success);
  });

  test('a miss breaks the streak when no freeze is banked', () {
    final s = computeStreak(
        [ev(17, onTime: true), ev(18, onTime: false), ev(19, onTime: true)], now);
    expect(s.current, 1); // 17 ok(1), 18 miss→0, 19 ok(1)
    expect(s.best, 1);
    expect(s.byDay[d(18)], DayOutcome.miss);
  });

  test('an earned freeze absorbs a miss and the streak holds', () {
    final days = [for (var i = 8; i <= 14; i++) ev(i, onTime: true)]; // 7 successes → 1 freeze
    days.add(ev(15, onTime: false)); // miss, absorbed
    days.add(ev(16, onTime: true)); // continues
    final s = computeStreak(days, now);
    expect(s.current, 8);
    expect(s.freezesRemaining, 0);
    expect(s.best, 8);
  });

  test('freezes are earned every 7 successes and cap at 2', () {
    final days = [for (var i = 1; i <= 14; i++) ev(i, onTime: true)]; // 14 straight
    final s = computeStreak(days, now);
    expect(s.current, 14);
    expect(s.freezesRemaining, 2);
  });

  test('no-alarm (neutral) days are skipped, not breaks', () {
    final s = computeStreak([ev(17, onTime: true), ev(19, onTime: true)], now); // 18 absent
    expect(s.current, 2);
    expect(s.byDay.containsKey(d(18)), isFalse);
  });

  test('today success extends the streak immediately', () {
    final s = computeStreak([ev(19, onTime: true), ev(20, onTime: true)], now);
    expect(s.current, 2);
    expect(s.byDay[d(20)], DayOutcome.success);
  });

  test('today pending holds the streak but does not extend it', () {
    final s = computeStreak(
        [ev(19, onTime: true), ev(20, onTime: false, open: true)], now);
    expect(s.current, 1);
    expect(s.byDay[d(20)], DayOutcome.pending);
  });

  test('a past never-dismissed event is a miss', () {
    final s = computeStreak(
        [ev(18, onTime: false, open: true), ev(19, onTime: true)], now);
    expect(s.byDay[d(18)], DayOutcome.miss);
    expect(s.current, 1);
  });

  test('any on-time event makes the whole day a success', () {
    final s = computeStreak(
        [ev(19, onTime: false), ev(19, onTime: true)], now);
    expect(s.byDay[d(19)], DayOutcome.success);
    expect(s.current, 1);
  });

  test('best streak survives a later reset', () {
    final days = [for (var i = 8; i <= 12; i++) ev(i, onTime: true)]; // 5 successes, no freeze yet
    days.add(ev(13, onTime: false)); // miss, nothing banked → resets run
    days.add(ev(14, onTime: true));
    days.add(ev(15, onTime: true)); // rebuild to 2
    final s = computeStreak(days, now);
    expect(s.current, 2);
    expect(s.best, 5); // best must outlive the reset
    expect(s.freezesRemaining, 0);
  });

  test('freezes never exceed the cap past the third threshold', () {
    final days = [for (var i = 1; i <= 21; i++) ev(i, onTime: true)]; // thresholds at 7, 14, 21
    final s = computeStreak(days, DateTime(2026, 7, 25, 12));
    expect(s.current, 21);
    expect(s.freezesRemaining, 2); // capped at 2, NOT 3
  });

  test('an excused rough-night miss holds the streak (no break, no advance)', () {
    // Without excusing, day 18 is a miss that breaks the run to 1.
    final events = [
      ev(17, onTime: true),
      ev(18, onTime: false),
      ev(19, onTime: true),
    ];
    final excused = computeStreak(events, now, excusedDays: {d(18)});
    expect(excused.current, 2, reason: 'excused miss neither breaks nor adds');
    expect(excused.byDay[d(18)], DayOutcome.neutral);
    // Sanity: the same log WITHOUT the excuse still breaks.
    expect(computeStreak(events, now).current, 1);
  });

  test('excusing a day does not advance the streak on its own', () {
    // Day 18 has rings but no on-time dismissal; excusing it must not count as
    // a success — the run is only the two on-time days around it.
    final events = [ev(18, onTime: false)];
    final s = computeStreak(events, now, excusedDays: {d(18)});
    expect(s.current, 0);
    expect(s.byDay[d(18)], DayOutcome.neutral);
  });

  test('excusing a non-miss day is a harmless no-op', () {
    final events = [ev(18, onTime: true), ev(19, onTime: true)];
    final s = computeStreak(events, now, excusedDays: {d(18), d(19)});
    expect(s.current, 2);
    expect(s.byDay[d(18)], DayOutcome.success);
  });

  test('a normal (unexcused) miss still breaks the streak', () {
    final s = computeStreak(
        [ev(17, onTime: true), ev(18, onTime: false), ev(19, onTime: true)],
        now,
        excusedDays: {d(16)}); // excusing an unrelated day changes nothing
    expect(s.current, 1);
    expect(s.byDay[d(18)], DayOutcome.miss);
  });

  test('a second miss after the freeze is spent resets the run', () {
    final days = [for (var i = 1; i <= 7; i++) ev(i, onTime: true)]; // run 7 → earn 1 freeze
    days.add(ev(8, onTime: false)); // miss absorbed by the freeze (run holds at 7)
    days.add(ev(9, onTime: false)); // miss with no freeze left → reset
    days.add(ev(10, onTime: true)); // rebuild to 1
    final s = computeStreak(days, now);
    expect(s.current, 1);
    expect(s.best, 7);
    expect(s.freezesRemaining, 0);
  });
}
