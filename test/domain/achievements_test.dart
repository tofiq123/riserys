import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/achievements.dart';
import 'package:rise/domain/streak.dart';
import 'package:rise/domain/wake_event.dart';

/// A completed wake-up on the local day of [dismissed], dismissed at that
/// instant. Ring time defaults to 06:00 that day.
WakeEvent ev(
  DateTime dismissed, {
  bool onTime = true,
  int snoozeCount = 0,
  int? alertnessScore,
  int id = 0,
}) {
  final ring =
      DateTime(dismissed.year, dismissed.month, dismissed.day, 6);
  return WakeEvent(
    id: id,
    alarmId: 1,
    scheduledAt: ring,
    firstRingAt: ring,
    dismissedAt: dismissed,
    onTime: onTime,
    snoozeCount: snoozeCount,
    alertnessScore: alertnessScore,
  );
}

/// An open (never dismissed) event — must not count anywhere.
WakeEvent open(DateTime day, {int id = 0}) {
  final ring = DateTime(day.year, day.month, day.day, 6);
  return WakeEvent(
      id: id, alarmId: 1, scheduledAt: ring, firstRingAt: ring, onTime: false);
}

Achievement badge(List<Achievement> xs, String id) =>
    xs.firstWhere((a) => a.id == id);

StreakStats streakWith({int current = 0, int best = 0}) =>
    StreakStats(current: current, best: best, freezesRemaining: 0, byDay: const {});

void main() {
  test('returns the full stable badge set even with no data', () {
    final xs = earnedAchievements(streak: streakWith(), events: const []);
    expect(xs.map((a) => a.id), [
      'first_light',
      'streak_7',
      'streak_30',
      'streak_100',
      'perfect_week',
      'no_snooze_week',
      'early_bird',
      'sharp',
    ]);
    expect(xs.every((a) => !a.earned), isTrue);
  });

  test('First light earns on the first completed wake-up', () {
    final none = earnedAchievements(streak: streakWith(), events: const []);
    expect(badge(none, 'first_light').earned, isFalse);
    expect(badge(none, 'first_light').progress, 0);

    final one = earnedAchievements(
        streak: streakWith(), events: [ev(DateTime(2026, 3, 1, 6, 3))]);
    expect(badge(one, 'first_light').earned, isTrue);
    expect(badge(one, 'first_light').fraction, 1.0);
  });

  test('First light does not earn on an open (undismissed) event', () {
    final xs = earnedAchievements(
        streak: streakWith(), events: [open(DateTime(2026, 3, 1))]);
    expect(badge(xs, 'first_light').earned, isFalse);
  });

  test('streak badges read from best streak and expose progress', () {
    final xs = earnedAchievements(
        streak: streakWith(current: 2, best: 9), events: const []);
    expect(badge(xs, 'streak_7').earned, isTrue); // 9 >= 7
    expect(badge(xs, 'streak_7').progress, 7); // clamped to target
    expect(badge(xs, 'streak_30').earned, isFalse);
    expect(badge(xs, 'streak_30').progress, 9);
    expect(badge(xs, 'streak_30').fraction, closeTo(9 / 30, 1e-9));
    expect(badge(xs, 'streak_100').earned, isFalse);
  });

  test('a badge earned by best streak stays earned after a later miss', () {
    // current dropped to 0 but best is 30 — the accomplishment holds.
    final xs = earnedAchievements(
        streak: streakWith(current: 0, best: 30), events: const []);
    expect(badge(xs, 'streak_7').earned, isTrue);
    expect(badge(xs, 'streak_30').earned, isTrue);
  });

  test('Perfect week needs 7 consecutive on-time calendar days', () {
    // Six in a row: not yet.
    final six = [
      for (var i = 1; i <= 6; i++) ev(DateTime(2026, 3, i, 6, 3), id: i),
    ];
    final xs6 = earnedAchievements(streak: streakWith(), events: six);
    expect(badge(xs6, 'perfect_week').earned, isFalse);
    expect(badge(xs6, 'perfect_week').progress, 6);

    // Seven in a row earns it.
    final seven = [
      for (var i = 1; i <= 7; i++) ev(DateTime(2026, 3, i, 6, 3), id: i),
    ];
    final xs7 = earnedAchievements(streak: streakWith(), events: seven);
    expect(badge(xs7, 'perfect_week').earned, isTrue);
  });

  test('Perfect week breaks on a late/miss day and on a calendar gap', () {
    // A miss on day 4 breaks the run into 3 + 3.
    final withMiss = [
      for (var i = 1; i <= 7; i++)
        ev(DateTime(2026, 3, i, 6, 3), onTime: i != 4, id: i),
    ];
    expect(
        badge(earnedAchievements(streak: streakWith(), events: withMiss),
                'perfect_week')
            .earned,
        isFalse);

    // A skipped calendar day (no event on day 4) also breaks adjacency.
    final withGap = [
      for (var i = 1; i <= 8; i++)
        if (i != 4) ev(DateTime(2026, 3, i, 6, 3), id: i),
    ];
    expect(
        badge(earnedAchievements(streak: streakWith(), events: withGap),
                'perfect_week')
            .earned,
        isFalse);
  });

  test('No-snooze week needs 7 straight snooze-free completed days', () {
    final clean = [
      for (var i = 1; i <= 7; i++)
        ev(DateTime(2026, 3, i, 6, 3), snoozeCount: 0, id: i),
    ];
    expect(
        badge(earnedAchievements(streak: streakWith(), events: clean),
                'no_snooze_week')
            .earned,
        isTrue);

    // One snoozed day inside the run breaks it (even though still on time).
    final snoozed = [
      for (var i = 1; i <= 7; i++)
        ev(DateTime(2026, 3, i, 6, 3), snoozeCount: i == 4 ? 2 : 0, id: i),
    ];
    expect(
        badge(earnedAchievements(streak: streakWith(), events: snoozed),
                'no_snooze_week')
            .earned,
        isFalse);
  });

  test('No-snooze week counts a day snoozed if ANY of its events snoozed', () {
    // Two events on day 3: one clean, one snoozed -> the day is not snooze-free.
    final events = <WakeEvent>[
      for (var i = 1; i <= 7; i++) ev(DateTime(2026, 3, i, 6, 3), id: i),
      ev(DateTime(2026, 3, 3, 7, 0), snoozeCount: 1, id: 99),
    ];
    expect(
        badge(earnedAchievements(streak: streakWith(), events: events),
                'no_snooze_week')
            .earned,
        isFalse);
  });

  test('Early bird counts dismissals before 6 AM and tracks progress', () {
    final early = [
      for (var i = 1; i <= 4; i++) ev(DateTime(2026, 3, i, 5, 40), id: i),
    ];
    final xs4 = earnedAchievements(streak: streakWith(), events: early);
    expect(badge(xs4, 'early_bird').earned, isFalse);
    expect(badge(xs4, 'early_bird').progress, 4);

    final five = [
      for (var i = 1; i <= 5; i++) ev(DateTime(2026, 3, i, 5, 59), id: i),
    ];
    expect(
        badge(earnedAchievements(streak: streakWith(), events: five),
                'early_bird')
            .earned,
        isTrue);
  });

  test('Early bird ignores wake-ups at or after 6 AM', () {
    final late = [
      for (var i = 1; i <= 6; i++) ev(DateTime(2026, 3, i, 6, 0), id: i),
    ];
    expect(
        badge(earnedAchievements(streak: streakWith(), events: late),
                'early_bird')
            .progress,
        0);
  });

  test('Sharp earns on any alertness score >= 80 and tracks the best', () {
    final mid = [
      ev(DateTime(2026, 3, 1, 6, 3), alertnessScore: 55, id: 1),
      ev(DateTime(2026, 3, 2, 6, 3), alertnessScore: 72, id: 2),
    ];
    final xsMid = earnedAchievements(streak: streakWith(), events: mid);
    expect(badge(xsMid, 'sharp').earned, isFalse);
    expect(badge(xsMid, 'sharp').progress, 72); // best-so-far toward 80

    final sharp = [
      ev(DateTime(2026, 3, 3, 6, 3), alertnessScore: 88, id: 3),
    ];
    expect(
        badge(earnedAchievements(streak: streakWith(), events: sharp), 'sharp')
            .earned,
        isTrue);
  });

  test('Sharp progress is 0 when no event carries an alertness score', () {
    final xs = earnedAchievements(
        streak: streakWith(), events: [ev(DateTime(2026, 3, 1, 6, 3))]);
    expect(badge(xs, 'sharp').progress, 0);
    expect(badge(xs, 'sharp').earned, isFalse);
  });
}
