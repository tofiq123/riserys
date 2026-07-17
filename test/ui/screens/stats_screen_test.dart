import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/streak.dart';
import 'package:rise/domain/wake_event.dart';
import 'package:rise/ui/screens/stats_screen.dart';
import 'package:rise/ui/state/wake_providers.dart';

WakeEvent evOn(DateTime day, {bool onTime = true}) {
  final ring = DateTime(day.year, day.month, day.day, 6);
  return WakeEvent(
    id: 0,
    alarmId: 1,
    scheduledAt: ring,
    firstRingAt: ring,
    dismissedAt: ring.add(Duration(minutes: onTime ? 3 : 30)),
    onTime: onTime,
    label: 'Run',
  );
}

Future<void> _pump(WidgetTester t, Widget w) async {
  t.view.physicalSize = const Size(1200, 4000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(w);
}

Widget _host({List<WakeEvent> events = const [], StreakStats streak = StreakStats.empty}) {
  return ProviderScope(
    overrides: [
      wakeEventsProvider.overrideWith((ref) => Stream.value(events)),
      streakProvider.overrideWithValue(streak),
    ],
    child: const MaterialApp(home: Scaffold(body: StatsScreen())),
  );
}

void main() {
  testWidgets('shows an empty state when there are no wake events', (t) async {
    await _pump(t, _host());
    await t.pump();
    expect(find.textContaining('No wake data'), findsOneWidget);
  });

  testWidgets('renders the streak card and section headers with data', (t) async {
    final today = DateTime.now();
    await _pump(t, _host(
      events: [evOn(today)],
      streak: const StreakStats(current: 4, best: 9, freezesRemaining: 1, byDay: {}),
    ));
    await t.pump();
    expect(find.text('4'), findsOneWidget); // current streak
    expect(find.text('9'), findsOneWidget); // best
    expect(find.text('LAST 30 DAYS'), findsOneWidget); // SectionLabel uppercases
    expect(find.text('THIS WEEK'), findsOneWidget);
  });

  test('consistencyLine reports the on-time count for the week', () {
    final now = DateTime(2026, 7, 20, 12);
    final events = [
      evOn(DateTime(2026, 7, 18)),
      evOn(DateTime(2026, 7, 19), onTime: false),
      evOn(DateTime(2026, 7, 20)),
    ];
    expect(consistencyLine(events, now), 'On time 2 of 3 this week.');
  });

  test('consistencyLine handles a week with no wake-ups', () {
    expect(consistencyLine(const [], DateTime(2026, 7, 20, 12)),
        'No wake-ups yet this week.');
  });

  test('weekWakes returns 7 days ending today, with per-day deltas', () {
    final now = DateTime(2026, 7, 20, 12);
    final wakes = weekWakes([evOn(DateTime(2026, 7, 20))], now);
    expect(wakes, hasLength(7));
    expect(wakes.last.day, DateTime(2026, 7, 20));
    expect(wakes.last.hasEvent, isTrue);
    expect(wakes.last.deltaMinutes, 3);
    expect(wakes.first.hasEvent, isFalse); // 6 days ago: no event
  });

  test('weekWakes prefers the on-time event over a later miss on the same day', () {
    final now = DateTime(2026, 7, 20, 12);
    final onTimeEarly = WakeEvent(
      id: 1,
      alarmId: 1,
      scheduledAt: DateTime(2026, 7, 20, 6),
      firstRingAt: DateTime(2026, 7, 20, 6),
      dismissedAt: DateTime(2026, 7, 20, 6, 3),
      onTime: true,
    );
    final lateMiss = WakeEvent(
      id: 2,
      alarmId: 1,
      scheduledAt: DateTime(2026, 7, 20, 6),
      firstRingAt: DateTime(2026, 7, 20, 7), // rang later
      dismissedAt: DateTime(2026, 7, 20, 7, 40),
      onTime: false,
    );
    // The on-time event represents the day even though the miss rang later.
    final wakes = weekWakes([lateMiss, onTimeEarly], now);
    expect(wakes.last.onTime, isTrue);
    expect(wakes.last.deltaMinutes, 3);
  });
}
