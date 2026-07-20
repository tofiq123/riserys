import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/adaptive_difficulty.dart';
import 'package:rise/domain/wake_event.dart';

/// A finalized wake-event, mission-dismissed by default. [minutesAgo] orders
/// events in time (larger = older) so tests can control the "most recent" window.
WakeEvent wake({
  required int minutesAgo,
  bool onTime = true,
  int failures = 0,
  String method = 'mission',
  bool open = false,
}) {
  final ring = DateTime.utc(2026, 7, 20, 6).subtract(Duration(minutes: minutesAgo));
  return WakeEvent(
    id: minutesAgo,
    alarmId: 1,
    scheduledAt: ring,
    firstRingAt: ring,
    dismissedAt: open ? null : ring.add(const Duration(minutes: 1)),
    method: method,
    onTime: onTime,
    missionFailures: failures,
  );
}

void main() {
  test('breezing (3 clean mission wakes) bumps one tier', () {
    final events = [wake(minutesAgo: 1), wake(minutesAgo: 2), wake(minutesAgo: 3)];
    expect(adaptiveDifficulty('easy', events), 'medium');
    expect(adaptiveDifficulty('medium', events), 'hard');
  });

  test('already at hard stays hard even when breezing', () {
    final events = [wake(minutesAgo: 1), wake(minutesAgo: 2), wake(minutesAgo: 3)];
    expect(adaptiveDifficulty('hard', events), 'hard');
  });

  test('an unknown base difficulty is returned unchanged', () {
    final events = [wake(minutesAgo: 1), wake(minutesAgo: 2), wake(minutesAgo: 3)];
    expect(adaptiveDifficulty('brutal', events), 'brutal');
  });

  test('too few mission wakes keeps the base difficulty', () {
    expect(adaptiveDifficulty('easy', []), 'easy');
    expect(
        adaptiveDifficulty('easy', [wake(minutesAgo: 1), wake(minutesAgo: 2)]),
        'easy');
  });

  test('struggling (a mission failure in the window) keeps the base', () {
    final events = [
      wake(minutesAgo: 1, failures: 1),
      wake(minutesAgo: 2),
      wake(minutesAgo: 3),
    ];
    expect(adaptiveDifficulty('easy', events), 'easy');
  });

  test('a late wake in the window keeps the base', () {
    final events = [
      wake(minutesAgo: 1, onTime: false),
      wake(minutesAgo: 2),
      wake(minutesAgo: 3),
    ];
    expect(adaptiveDifficulty('easy', events), 'easy');
  });

  test('non-mission dismissals do not count toward the window', () {
    // Three clean slide dismissals + two clean mission ones = only 2 mission
    // wakes, below the window, so no bump.
    final events = [
      wake(minutesAgo: 1, method: 'slide'),
      wake(minutesAgo: 2, method: 'slide'),
      wake(minutesAgo: 3, method: 'slide'),
      wake(minutesAgo: 4),
      wake(minutesAgo: 5),
    ];
    expect(adaptiveDifficulty('easy', events), 'easy');
  });

  test('still-open events do not count toward the window', () {
    final events = [
      wake(minutesAgo: 1, open: true),
      wake(minutesAgo: 2),
      wake(minutesAgo: 3),
    ];
    expect(adaptiveDifficulty('easy', events), 'easy');
  });

  test('only the most recent three mission wakes decide it', () {
    // The three most recent are clean; an older struggle is outside the window.
    final recentCleanOldDirty = [
      wake(minutesAgo: 1),
      wake(minutesAgo: 2),
      wake(minutesAgo: 3),
      wake(minutesAgo: 99, failures: 2),
    ];
    expect(adaptiveDifficulty('easy', recentCleanOldDirty), 'medium');

    // A recent struggle blocks the bump even though older wakes were clean.
    final recentDirtyOldClean = [
      wake(minutesAgo: 1, failures: 1),
      wake(minutesAgo: 2),
      wake(minutesAgo: 3),
      wake(minutesAgo: 98),
      wake(minutesAgo: 99),
    ];
    expect(adaptiveDifficulty('easy', recentDirtyOldClean), 'easy');
  });

  test('event order in the input list does not matter (sorted internally)', () {
    final shuffled = [wake(minutesAgo: 3), wake(minutesAgo: 1), wake(minutesAgo: 2)];
    expect(adaptiveDifficulty('easy', shuffled), 'medium');
  });
}
