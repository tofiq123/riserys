import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/period_stats.dart';
import 'package:rise/domain/wake_event.dart';

/// A completed wake-up on [day], dismissed at [h]:[m] local, on time by default.
WakeEvent ev(DateTime day, {int h = 6, int m = 3, bool onTime = true, int id = 0}) {
  final ring = DateTime(day.year, day.month, day.day, 6);
  return WakeEvent(
    id: id,
    alarmId: 1,
    scheduledAt: ring,
    firstRingAt: ring,
    dismissedAt: DateTime(day.year, day.month, day.day, h, m),
    onTime: onTime,
  );
}

WakeEvent open(DateTime day, {int id = 0}) {
  final ring = DateTime(day.year, day.month, day.day, 6);
  return WakeEvent(
      id: id, alarmId: 1, scheduledAt: ring, firstRingAt: ring, onTime: false);
}

void main() {
  final now = DateTime(2026, 7, 20, 12); // a Monday noon

  test('period window lengths', () {
    expect(periodDays(StatsPeriod.week), 7);
    expect(periodDays(StatsPeriod.month), 30);
    expect(periodDays(StatsPeriod.year), 365);
  });

  test('empty log yields empty stats and null rates', () {
    final s = aggregatePeriod(const [], now, StatsPeriod.month);
    expect(s, PeriodStats.empty);
    expect(s.onTimeRate, isNull);
    expect(s.avgWakeMinute, isNull);
  });

  test('week window includes only the trailing 7 days', () {
    final events = [
      ev(DateTime(2026, 7, 20), id: 1), // today
      ev(DateTime(2026, 7, 14), id: 2), // 6 days ago -> in
      ev(DateTime(2026, 7, 13), id: 3), // 7 days ago -> out
    ];
    final s = aggregatePeriod(events, now, StatsPeriod.week);
    expect(s.count, 2);
  });

  test('month spans a trailing 30 days; year a trailing 365 (today + N-1)', () {
    // month window: 2026-06-21 .. 2026-07-20 inclusive (30 days).
    // year window:  2025-07-21 .. 2026-07-20 inclusive (365 days).
    final events = [
      ev(DateTime(2026, 7, 20), id: 1), // today -> in both
      ev(DateTime(2026, 6, 21), id: 2), // 29 days ago -> oldest in month
      ev(DateTime(2026, 6, 20), id: 3), // 30 days ago -> just out of month
      ev(DateTime(2026, 6, 19), id: 4), // 31 days ago -> out of month, in year
      ev(DateTime(2025, 7, 21), id: 5), // 364 days ago -> oldest in year
      ev(DateTime(2025, 7, 20), id: 6), // 365 days ago -> just out of year
      ev(DateTime(2025, 7, 19), id: 7), // out of year
    ];
    // month: ids 1, 2.
    expect(aggregatePeriod(events, now, StatsPeriod.month).count, 2);
    // year: ids 1, 2, 3, 4, 5.
    expect(aggregatePeriod(events, now, StatsPeriod.year).count, 5);
  });

  test('on-time rate and count ignore open events', () {
    final events = [
      ev(DateTime(2026, 7, 18), id: 1),
      ev(DateTime(2026, 7, 19), onTime: false, id: 2),
      ev(DateTime(2026, 7, 20), id: 3),
      open(DateTime(2026, 7, 20), id: 4), // not dismissed -> ignored
    ];
    final s = aggregatePeriod(events, now, StatsPeriod.week);
    expect(s.count, 3);
    expect(s.onTimeCount, 2);
    expect(s.onTimeRate, closeTo(2 / 3, 1e-9));
  });

  test('average wake time is the mean dismissal minute-of-day', () {
    final events = [
      ev(DateTime(2026, 7, 18), h: 6, m: 0, id: 1), // 360
      ev(DateTime(2026, 7, 19), h: 7, m: 0, id: 2), // 420
      ev(DateTime(2026, 7, 20), h: 6, m: 30, id: 3), // 390
    ];
    // mean(360,420,390) = 390 -> 06:30
    expect(aggregatePeriod(events, now, StatsPeriod.week).avgWakeMinute, 390);
  });

  test('best streak is the longest consecutive on-time day run in the window', () {
    final events = [
      ev(DateTime(2026, 7, 15), id: 1),
      ev(DateTime(2026, 7, 16), id: 2),
      ev(DateTime(2026, 7, 17), onTime: false, id: 3), // breaks the run
      ev(DateTime(2026, 7, 18), id: 4),
      ev(DateTime(2026, 7, 19), id: 5),
      ev(DateTime(2026, 7, 20), id: 6), // 18-19-20 -> run of 3
    ];
    expect(aggregatePeriod(events, now, StatsPeriod.week).bestStreak, 3);
  });

  test('an out-of-window on-time run does not count toward best streak', () {
    // A 5-day on-time run entirely older than a week is excluded from the week.
    final events = [
      for (var d = 8; d <= 12; d++) ev(DateTime(2026, 7, d), id: d),
    ];
    expect(aggregatePeriod(events, now, StatsPeriod.week).bestStreak, 0);
    expect(aggregatePeriod(events, now, StatsPeriod.month).bestStreak, 5);
  });
}
