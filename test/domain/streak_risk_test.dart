import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/streak.dart';
import 'package:rise/domain/streak_risk.dart';

final _now = DateTime(2026, 7, 20, 9); // a fixed morning
final _today = DateTime(2026, 7, 20);
final _yesterday = DateTime(2026, 7, 19);

StreakStats _stats(int current, Map<DateTime, DayOutcome> byDay) =>
    StreakStats(current: current, best: current, freezesRemaining: 0, byDay: byDay);

void main() {
  test('a fresh break (yesterday miss, run reset to 0) -> broke', () {
    expect(streakRisk(_stats(0, {_yesterday: DayOutcome.miss}), _now),
        StreakRisk.broke);
  });

  test('a live streak with today still pending -> atRisk', () {
    expect(streakRisk(_stats(4, {_today: DayOutcome.pending}), _now),
        StreakRisk.atRisk);
  });

  test('a miss held by a freeze (run intact) is atRisk when today pending, '
      'not broke', () {
    final stats = _stats(5, {
      _yesterday: DayOutcome.miss,
      _today: DayOutcome.pending,
    });
    expect(streakRisk(stats, _now), StreakRisk.atRisk);
  });

  test('broke takes precedence over atRisk', () {
    final stats = _stats(0, {
      _yesterday: DayOutcome.miss,
      _today: DayOutcome.pending,
    });
    expect(streakRisk(stats, _now), StreakRisk.broke);
  });

  test('today already a success -> none', () {
    expect(streakRisk(_stats(4, {_today: DayOutcome.success}), _now),
        StreakRisk.none);
  });

  test('today pending but no streak to protect -> none', () {
    expect(streakRisk(_stats(0, {_today: DayOutcome.pending}), _now),
        StreakRisk.none);
  });

  test('an old lapse (miss not yesterday) does not read as a fresh break', () {
    final threeDaysAgo = _today.subtract(const Duration(days: 3));
    expect(streakRisk(_stats(0, {threeDaysAgo: DayOutcome.miss}), _now),
        StreakRisk.none);
  });

  test('empty stats -> none', () {
    expect(streakRisk(StreakStats.empty, _now), StreakRisk.none);
  });
}
