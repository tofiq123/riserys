import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/auth/auth_service.dart';
import 'package:rise/data/leaderboard/leaderboard_service.dart';
import 'package:rise/domain/crew_standing.dart';
import 'package:rise/domain/streak.dart';
import 'package:rise/domain/wake_event.dart';
import 'package:rise/domain/wake_stats.dart';
import 'package:rise/ui/screens/stats_screen.dart';
import 'package:rise/ui/state/auth_providers.dart';
import 'package:rise/ui/state/leaderboard_providers.dart';
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

CrewStanding _standing(String id, String username, int streak, {bool isMe = false}) =>
    CrewStanding(
      id: id,
      username: username,
      displayName: username,
      avatarColor: '#7C9CF4',
      stats: WakeStats(currentStreak: streak, totalWakes: 10, onTimeCount: 8),
      isMe: isMe,
    );

Future<void> _pumpSignedIn(WidgetTester t, {List<CrewStanding> standings = const []}) async {
  final auth = FakeAuthService();
  await auth.signInWithGoogle();
  await auth.claimUsername('me', displayName: 'Me');
  addTearDown(auth.dispose);
  t.view.physicalSize = const Size(1200, 4000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [
      wakeEventsProvider.overrideWith((ref) => Stream.value(const [])),
      streakProvider.overrideWithValue(StreakStats.empty),
      authServiceProvider.overrideWithValue(auth),
      leaderboardServiceProvider.overrideWithValue(
          FakeLeaderboardService(standings: standings)),
    ],
    child: const MaterialApp(home: Scaffold(body: StatsScreen())),
  ));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('signed out shows the leaderboard sign-in prompt', (t) async {
    await _pump(t, _host()); // default providers -> account null
    await t.pumpAndSettle();
    expect(find.textContaining('Sign in from the Profile tab'), findsOneWidget);
  });

  testWidgets('signed in renders the ranked crew leaderboard', (t) async {
    await _pumpSignedIn(t, standings: [
      _standing('fake-uid', 'me', 5, isMe: true),
      _standing('u2', 'bo', 3),
    ]);
    expect(find.text('CREW LEADERBOARD'), findsOneWidget); // SectionLabel uppercases
    expect(find.textContaining('@me'), findsOneWidget);
    expect(find.textContaining('@bo'), findsOneWidget);
  });

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
