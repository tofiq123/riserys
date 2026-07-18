import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/streak.dart';
import 'package:rise/domain/wake_event.dart';
import 'package:rise/domain/wake_stats.dart';

WakeEvent _e(int id, {DateTime? dismissedAt, bool onTime = false}) => WakeEvent(
      id: id,
      alarmId: 1,
      scheduledAt: DateTime.utc(2026, 7, 18, 6),
      firstRingAt: DateTime.utc(2026, 7, 18, 6),
      dismissedAt: dismissedAt,
      onTime: onTime,
    );

void main() {
  test('onTimeRate is 0 when there are no wakes', () {
    expect(const WakeStats().onTimeRate, 0);
    expect(const WakeStats(totalWakes: 0, onTimeCount: 0).onTimeRate, 0);
  });

  test('onTimeRate is the fraction of on-time wakes', () {
    expect(const WakeStats(totalWakes: 4, onTimeCount: 3).onTimeRate, 0.75);
  });

  test('computeWakeStats counts only finalized events; passes streak through', () {
    final now = DateTime.utc(2026, 7, 18, 6);
    final events = [
      _e(1, dismissedAt: now, onTime: true),
      _e(2, dismissedAt: now, onTime: false),
      _e(3, dismissedAt: now, onTime: true),
      _e(4), // open (dismissedAt null) -> not counted
    ];
    const streak = StreakStats(current: 5, best: 9, freezesRemaining: 2, byDay: {});
    final s = computeWakeStats(events, streak);
    expect(s.currentStreak, 5);
    expect(s.bestStreak, 9);
    expect(s.totalWakes, 3);
    expect(s.onTimeCount, 2);
  });

  test('value equality', () {
    expect(const WakeStats(currentStreak: 1, totalWakes: 2),
        const WakeStats(currentStreak: 1, totalWakes: 2));
    expect(const WakeStats(currentStreak: 1).hashCode,
        const WakeStats(currentStreak: 1).hashCode);
    expect(const WakeStats(currentStreak: 1),
        isNot(const WakeStats(currentStreak: 2)));
  });
}
