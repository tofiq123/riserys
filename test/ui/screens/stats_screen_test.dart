import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/auth/auth_service.dart';
import 'package:rise/data/crew/crew_service.dart';
import 'package:rise/data/leaderboard/leaderboard_service.dart';
import 'package:rise/data/local/database.dart';
import 'package:rise/data/local/excused_days_repository.dart';
import 'package:rise/data/nudge/nudge_service.dart';
import 'package:rise/domain/crew_member.dart';
import 'package:rise/domain/crew_standing.dart';
import 'package:rise/domain/crew_state.dart';
import 'package:rise/domain/streak.dart';
import 'package:rise/domain/wake_event.dart';
import 'package:rise/domain/wake_stats.dart';
import 'package:rise/ui/components/sparkline.dart';
import 'package:rise/ui/screens/stats_screen.dart';
import 'package:rise/ui/state/auth_providers.dart';
import 'package:rise/ui/state/crew_providers.dart';
import 'package:rise/ui/state/leaderboard_providers.dart';
import 'package:rise/ui/state/nudge_providers.dart';
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

/// A dismissed event carrying an alertness [score] (or none). [order] varies
/// firstRingAt so "latest" is deterministic.
WakeEvent evScore(int? score, {int order = 0}) {
  final ring = DateTime(2026, 7, 20, 6);
  return WakeEvent(
    id: order,
    alarmId: 1,
    scheduledAt: ring,
    firstRingAt: ring.add(Duration(minutes: order)),
    dismissedAt: ring.add(const Duration(minutes: 3)),
    onTime: true,
    label: 'Run',
    alertnessScore: score,
  );
}

Future<void> _pump(WidgetTester t, Widget w) async {
  t.view.physicalSize = const Size(1200, 4000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(w);
}

Widget _host(
    {List<WakeEvent> events = const [],
    StreakStats streak = StreakStats.empty,
    Future<void> Function(GlobalKey)? shareRunner}) {
  return ProviderScope(
    overrides: [
      wakeEventsProvider.overrideWith((ref) => Stream.value(events)),
      streakProvider.overrideWithValue(streak),
    ],
    child: MaterialApp(
        home: Scaffold(body: StatsScreen(shareRunner: shareRunner))),
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

CrewMember _member(String id, String username) => CrewMember(
    id: id, username: username, displayName: username, avatarColor: '#7C9CF4');

/// Pumps the Stats screen signed-in with a controllable streak + crew, for the
/// accountability-ping card. Returns the [FakeNudgeService] so the ping's fan
/// out can be asserted.
Future<FakeNudgeService> _pumpPing(
  WidgetTester t, {
  required StreakStats streak,
  List<CrewMember> friends = const [],
}) async {
  final auth = FakeAuthService();
  await auth.signInWithGoogle();
  await auth.claimUsername('me', displayName: 'Me');
  addTearDown(auth.dispose);
  final crew = FakeCrewService(
      selfId: auth.current!.id, initial: CrewState(friends: friends));
  addTearDown(crew.dispose);
  final nudge = FakeNudgeService();

  t.view.physicalSize = const Size(1200, 6000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [
      wakeEventsProvider
          .overrideWith((ref) => Stream.value([evOn(DateTime.now())])),
      streakProvider.overrideWithValue(streak),
      authServiceProvider.overrideWithValue(auth),
      crewServiceProvider.overrideWithValue(crew),
      nudgeServiceProvider.overrideWithValue(nudge),
      leaderboardServiceProvider
          .overrideWithValue(FakeLeaderboardService()),
    ],
    child: const MaterialApp(home: Scaffold(body: StatsScreen())),
  ));
  await t.pumpAndSettle();
  return nudge;
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

  testWidgets('shows the hybrid crew score with your contribution', (t) async {
    await _pumpSignedIn(t, standings: [
      _standing('fake-uid', 'me', 5, isMe: true),
      _standing('u2', 'bo', 3),
    ]);
    // Group aggregate + the signed-in user's individual share.
    expect(find.text('crew score'), findsOneWidget);
    expect(find.textContaining('Your part:'), findsOneWidget);
  });

  testWidgets('tapping a crew member on the leaderboard opens their detail',
      (t) async {
    await _pumpSignedIn(t, standings: [
      _standing('fake-uid', 'me', 5, isMe: true),
      _standing('u2', 'bo', 3),
    ]);
    await t.tap(find.text('bo')); // bo's row (display name)
    await t.pumpAndSettle();
    // The friend detail screen's own section label — only present there.
    expect(find.text('THEIR WAKE-UPS'), findsOneWidget);
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
    // Too little data for insights — the patterns section stays hidden.
    expect(find.text('YOUR PATTERNS'), findsNothing);
  });

  testWidgets('surfaces honest insights once there is enough data', (t) async {
    // Five completed, on-time wake-ups clears the minimum-event gate.
    final events = [
      for (var d = 20; d <= 24; d++) evOn(DateTime(2026, 7, d)),
    ];
    await _pump(t, _host(events: events));
    await t.pump();
    expect(find.text('YOUR PATTERNS'), findsOneWidget); // SectionLabel uppercases
    expect(find.textContaining('woke on time on 100%'), findsOneWidget);
    expect(find.textContaining('not judgements'), findsOneWidget);
  });

  testWidgets('rough-night affordance excuses the chosen day', (t) async {
    final db = RiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = ExcusedDaysRepository(db);

    t.view.physicalSize = const Size(1200, 4000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        wakeEventsProvider
            .overrideWith((ref) => Stream.value([evOn(DateTime.now())])),
        streakProvider.overrideWithValue(
            const StreakStats(current: 3, best: 3, freezesRemaining: 0, byDay: {})),
        // The card only needs a plain stream for display; the real repo (below)
        // handles the tap. Using the repo's drift watchAll() stream here would
        // leave a pending stream-close timer at teardown.
        excusedDaysProvider
            .overrideWith((ref) => Stream.value(const <DateTime>{})),
        excusedDaysRepositoryProvider.overrideWithValue(repo),
      ],
      child: const MaterialApp(home: Scaffold(body: StatsScreen())),
    ));
    await t.pumpAndSettle();

    expect(find.text('Rough night?'), findsOneWidget);
    await t.tap(find.byKey(const Key('rough-night-card')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('rough-today')));
    await t.pumpAndSettle();

    final days = await repo.all();
    expect(days, hasLength(1));
    expect(days.single, ExcusedDaysRepository.dayOf(DateTime.now()));
  });

  test('averageAlertness averages non-null scores (rounded), else null', () {
    expect(averageAlertness([evScore(80, order: 1), evScore(null, order: 2), evScore(90, order: 3)]), 85);
    expect(averageAlertness([evScore(70, order: 1), evScore(75, order: 2)]), 73); // 72.5 -> 73
    expect(averageAlertness(const []), isNull);
    expect(averageAlertness([evScore(null, order: 1), evScore(null, order: 2)]), isNull);
  });

  test('alertnessBand labels scores with neutral, non-diagnostic descriptors', () {
    expect(alertnessBand(80), 'sharp');
    expect(alertnessBand(95), 'sharp');
    expect(alertnessBand(50), 'steady');
    expect(alertnessBand(79), 'steady');
    expect(alertnessBand(49), 'groggy');
    expect(alertnessBand(0), 'groggy');
  });

  testWidgets('Alertness card shows the latest score, average, and honest subtext',
      (t) async {
    await _pump(t, _host(events: [
      evScore(60, order: 1),
      evScore(84, order: 2), // latest (greatest firstRingAt)
    ]));
    await t.pump();
    expect(find.text('ALERTNESS'), findsOneWidget); // SectionLabel uppercases
    expect(find.text('84'), findsOneWidget); // latest score
    expect(find.text('72'), findsOneWidget); // average of 60 and 84
    expect(find.text('sharp'), findsOneWidget); // 84 -> neutral band
    expect(
        find.text(
            'Your reaction speed at wake-up — sharper is more awake. '
            'Not a medical measure.'),
        findsOneWidget);
  });

  testWidgets('Alertness card shows a placeholder when no event carries a score',
      (t) async {
    await _pump(t, _host(events: [evOn(DateTime.now())])); // wake event, no PVT score
    await t.pump();
    expect(find.text('ALERTNESS'), findsOneWidget);
    expect(find.textContaining('No alertness scores yet'), findsOneWidget);
    expect(find.textContaining('Alertness (PVT)'), findsOneWidget);
    // The honest subtext only accompanies real scores, so it is absent here.
    expect(find.textContaining('Not a medical measure'), findsNothing);
  });

  testWidgets('renders the achievements wall with earned and locked badges',
      (t) async {
    // One completed wake-up: First light earns; the streak badges stay locked.
    await _pump(t, _host(events: [evOn(DateTime.now())]));
    await t.pump();
    expect(find.text('ACHIEVEMENTS'), findsOneWidget); // SectionLabel uppercases
    expect(find.text('First light'), findsOneWidget); // earned
    expect(find.text('7-day streak'), findsOneWidget); // locked, still shown
    expect(find.text('1 / 8'), findsOneWidget); // one of eight badges earned
  });

  testWidgets('surfaces a consistency score once there is enough data',
      (t) async {
    // Six wake-ups all dismissed at 06:03 -> perfectly regular -> 100.
    final events = [for (var d = 20; d <= 25; d++) evOn(DateTime(2026, 3, d))];
    await _pump(t, _host(events: events));
    await t.pump();
    expect(find.text('CONSISTENCY'), findsOneWidget); // SectionLabel uppercases
    expect(find.text('very steady'), findsOneWidget); // band for a top score
  });

  testWidgets('shows the alertness trend section once enough scores exist',
      (t) async {
    final events = [
      evScore(45, order: 1),
      evScore(50, order: 2),
      evScore(78, order: 3),
      evScore(82, order: 4), // rising over time -> Trending up
    ];
    await _pump(t, _host(events: events));
    await t.pump();
    expect(find.text('ALERTNESS TREND'), findsOneWidget);
    expect(find.text('Trending up'), findsOneWidget);
    expect(find.byType(Sparkline), findsOneWidget);
  });

  testWidgets('share affordance runs the share step on tap', (t) async {
    GlobalKey? captured;
    await _pump(t, _host(
      events: [evOn(DateTime.now())],
      shareRunner: (key) async => captured = key,
    ));
    await t.pump();
    expect(find.byKey(const Key('share-stats-card')), findsOneWidget);
    await t.tap(find.byKey(const Key('share-stats-card')));
    await t.pumpAndSettle();
    expect(captured, isNotNull); // the injected runner was invoked
    // A clean run shows no error snackbar.
    expect(find.textContaining('Couldn\'t share'), findsNothing);
  });

  testWidgets('share failure surfaces a graceful snackbar, never a crash',
      (t) async {
    await _pump(t, _host(
      events: [evOn(DateTime.now())],
      shareRunner: (key) async => throw Exception('boom'),
    ));
    await t.pump();
    await t.tap(find.byKey(const Key('share-stats-card')));
    await t.pumpAndSettle();
    expect(find.textContaining('Couldn\'t share right now'), findsOneWidget);
  });

  testWidgets('overview toggles between Week, Month and Year aggregates',
      (t) async {
    // Five on-time days this week, plus an older day only the Month/Year see.
    final today = DateTime.now();
    final events = [
      for (var i = 0; i < 5; i++)
        evOn(today.subtract(Duration(days: i))),
      evOn(today.subtract(const Duration(days: 20))), // outside the week window
    ];
    await _pump(t, _host(events: events));
    await t.pump();

    expect(find.text('OVERVIEW'), findsOneWidget); // SectionLabel uppercases
    expect(find.text('Week'), findsOneWidget);
    expect(find.text('Month'), findsOneWidget);
    expect(find.text('Year'), findsOneWidget);
    // Week: 5 of 5 on time.
    expect(find.text('5/5'), findsOneWidget);

    // Switch to Month: now 6 of 6.
    await t.tap(find.text('Month'));
    await t.pumpAndSettle();
    expect(find.text('6/6'), findsOneWidget);
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

  group('accountability ping', () {
    StreakStats atRiskToday() {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      return StreakStats(
          current: 3,
          best: 3,
          freezesRemaining: 0,
          byDay: {today: DayOutcome.pending});
    }

    testWidgets('appears when the streak is on the line and crew exists',
        (t) async {
      await _pumpPing(t,
          streak: atRiskToday(), friends: [_member('u1', 'ada')]);
      expect(
          find.byKey(const Key('accountability-ping-card')), findsOneWidget);
    });

    testWidgets('confirm pings every crew member via the nudge path',
        (t) async {
      final nudge = await _pumpPing(t,
          streak: atRiskToday(),
          friends: [_member('u1', 'ada'), _member('u2', 'bo')]);
      await t.tap(find.byKey(const Key('accountability-ping-card')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('accountability-ping-confirm')));
      await t.pumpAndSettle();
      // Reuses the existing single-target nudge, once per crew member.
      expect(nudge.nudgeCount, 2);
      expect(find.textContaining('Your crew knows'), findsOneWidget);
    });

    testWidgets('hidden when the streak is not at risk', (t) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      await _pumpPing(t,
          streak: StreakStats(
              current: 4,
              best: 4,
              freezesRemaining: 0,
              byDay: {today: DayOutcome.success}),
          friends: [_member('u1', 'ada')]);
      expect(find.byKey(const Key('accountability-ping-card')), findsNothing);
    });

    testWidgets('hidden when there is no crew to tell', (t) async {
      await _pumpPing(t, streak: atRiskToday(), friends: const []);
      expect(find.byKey(const Key('accountability-ping-card')), findsNothing);
    });
  });
}
