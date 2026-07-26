import 'dart:async';

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
import 'package:rise/domain/alertness_trend.dart';
import 'package:rise/domain/crew_member.dart';
import 'package:rise/domain/crew_standing.dart';
import 'package:rise/domain/crew_state.dart';
import 'package:rise/domain/streak.dart';
import 'package:rise/domain/wake_event.dart';
import 'package:rise/domain/wake_stats.dart';
import 'package:rise/ui/components/consistency_grid.dart';
import 'package:rise/ui/components/medallion_rail.dart';
import 'package:rise/ui/components/podium.dart';
import 'package:rise/ui/components/rise_skeleton.dart';
import 'package:rise/ui/components/rise_spinner.dart';
import 'package:rise/ui/components/sparkline.dart';
import 'package:rise/ui/components/stat_summary.dart';
import 'package:rise/ui/components/wake_rhythm_chart.dart';
import 'package:rise/ui/screens/friend_detail_screen.dart';
import 'package:rise/ui/screens/stats_screen.dart';
import 'package:rise/ui/state/auth_providers.dart';
import 'package:rise/ui/state/crew_providers.dart';
import 'package:rise/ui/state/leaderboard_providers.dart';
import 'package:rise/ui/state/nudge_providers.dart';
import 'package:rise/ui/state/wake_providers.dart';

/// Pinned "today" so the rhythm window and the grid are deterministic.
final _now = DateTime(2026, 7, 26, 12);

WakeEvent evOn(DateTime day, {bool onTime = true}) {
  final ring = DateTime(day.year, day.month, day.day, 6);
  return WakeEvent(
    id: day.day + day.month * 100,
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
  final ring = DateTime(2026, 7, 26, 6);
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

Widget _host({
  List<WakeEvent> events = const [],
  StreakStats streak = StreakStats.empty,
  Future<void> Function(GlobalKey)? shareRunner,
}) {
  return ProviderScope(
    overrides: [
      wakeEventsProvider.overrideWith((ref) => Stream.value(events)),
      streakProvider.overrideWithValue(streak),
    ],
    child: MaterialApp(
        home: Scaffold(
            body: StatsScreen(shareRunner: shareRunner, clock: _now))),
  );
}

/// Scopes a text finder to the summary block — "on time" also labels a mark in
/// the Rhythm lens's legend, and both are correct.
Finder _inSummary(String text) => find.descendant(
    of: find.byType(StatSummary), matching: find.text(text));

/// Switches the body to one of the three lenses.
Future<void> _lens(WidgetTester t, String label) async {
  await t.tap(find.text(label));
  await t.pumpAndSettle();
}

CrewStanding _standing(String id, String username, int streak,
        {bool isMe = false}) =>
    CrewStanding(
      id: id,
      username: username,
      displayName: username,
      avatarColor: '#7C9CF4',
      stats: WakeStats(currentStreak: streak, totalWakes: 10, onTimeCount: 8),
      isMe: isMe,
    );

Future<void> _pumpSignedIn(WidgetTester t,
    {List<CrewStanding> standings = const []}) async {
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
      leaderboardServiceProvider
          .overrideWithValue(FakeLeaderboardService(standings: standings)),
    ],
    child: MaterialApp(home: Scaffold(body: StatsScreen(clock: _now))),
  ));
  await t.pumpAndSettle();
  await _lens(t, 'Crew');
}

/// A live run whose today has rung but not yet succeeded — the one shape
/// streakRisk treats as "on the line".
StreakStats _pendingToday(int current) => StreakStats(
      current: current,
      best: current,
      freezesRemaining: 0,
      byDay: {ExcusedDaysRepository.dayOf(DateTime.now()): DayOutcome.pending},
    );

CrewMember _member(String id, String username) => CrewMember(
    id: id, username: username, displayName: username, avatarColor: '#7C9CF4');

/// A leaderboard whose fetch never completes — the first-load window.
class _PendingLeaderboardService extends FakeLeaderboardService {
  @override
  Future<List<CrewStanding>> fetchLeaderboard() =>
      Completer<List<CrewStanding>>().future;
}

/// Pumps Stats signed-in with a controllable streak + crew, for the streak-risk
/// banner. Returns the [FakeNudgeService] so the ping's fan-out can be asserted.
Future<FakeNudgeService> _pumpRisk(
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
      leaderboardServiceProvider.overrideWithValue(FakeLeaderboardService()),
    ],
    child: const MaterialApp(home: Scaffold(body: StatsScreen())),
  ));
  await t.pumpAndSettle();
  await _lens(t, 'Progress');
  return nudge;
}

void main() {
  group('the summary block', () {
    testWidgets('no data: a zero run is a starting line, not a placeholder',
        (t) async {
      await _pump(t, _host());
      await t.pumpAndSettle();
      expect(find.text('Your mornings'), findsOneWidget);
      expect(find.text('CURRENT RUN'), findsOneWidget);
      expect(_inSummary('0'), findsWidgets, reason: 'a zero run still renders');
      expect(find.text('No mornings logged this week yet.'), findsOneWidget);
      expect(find.textContaining('No wake data'), findsNothing);
    });

    testWidgets('the four figures sit together where they can be compared',
        (t) async {
      final events = [
        for (var d = 20; d <= 26; d++) evOn(DateTime(2026, 7, d))
      ];
      await _pump(t, _host(
        events: events,
        streak: const StreakStats(
            current: 4, best: 9, freezesRemaining: 1, byDay: {}),
      ));
      await t.pumpAndSettle();
      expect(_inSummary('4'), findsWidgets); // the run
      for (final label in ['on time', 'avg wake', 'best run', 'consistency']) {
        expect(_inSummary(label), findsOneWidget, reason: label);
      }
      final ys = [
        for (final l in ['on time', 'avg wake', 'best run', 'consistency'])
          t.getTopLeft(_inSummary(l)).dy
      ];
      expect(ys.toSet(), hasLength(1), reason: 'one row, so they compare');
    });

    testWidgets('the period control switches the figures', (t) async {
      final today = DateTime(2026, 7, 26);
      final events = [
        for (var i = 0; i < 5; i++) evOn(today.subtract(Duration(days: i))),
        evOn(today.subtract(const Duration(days: 20))), // month/year only
      ];
      await _pump(t, _host(events: events));
      await t.pumpAndSettle();

      expect(find.text('Week'), findsOneWidget);
      expect(find.text('Month'), findsOneWidget);
      expect(find.text('Year'), findsOneWidget);
      expect(find.text('5/5'), findsOneWidget);

      await t.tap(find.byKey(const Key('summary-period-month')));
      await t.pumpAndSettle();
      expect(find.text('6/6'), findsOneWidget);
    });
  });

  group('lenses', () {
    testWidgets('each lens shows its own body and only its own', (t) async {
      await _pump(t, _host(events: [evOn(DateTime(2026, 7, 26))]));
      await t.pumpAndSettle();

      // Rhythm is the default.
      expect(find.text('WHEN YOU ACTUALLY GET UP'), findsOneWidget);
      expect(find.text('ALERTNESS'), findsNothing);
      expect(find.text('CREW LEADERBOARD'), findsNothing);

      await _lens(t, 'Progress');
      expect(find.text('WHEN YOU ACTUALLY GET UP'), findsNothing);
      expect(find.text('ALERTNESS'), findsOneWidget);
      expect(find.text('STREAK'), findsOneWidget);

      await _lens(t, 'Crew');
      expect(find.text('ALERTNESS'), findsNothing);
      expect(find.text('CREW LEADERBOARD'), findsOneWidget);
    });

    testWidgets('the summary stays put across every lens', (t) async {
      await _pump(t, _host(events: [evOn(DateTime(2026, 7, 26))]));
      await t.pumpAndSettle();
      for (final lens in ['Progress', 'Crew', 'Rhythm']) {
        await _lens(t, lens);
        expect(find.text('CURRENT RUN'), findsOneWidget, reason: lens);
      }
    });
  });

  group('Rhythm lens', () {
    testWidgets('charts the fortnight and the five-week grid', (t) async {
      final events = [
        for (var d = 13; d <= 26; d++) evOn(DateTime(2026, 7, d))
      ];
      await _pump(t, _host(events: events));
      await t.pumpAndSettle();
      expect(find.byType(WakeRhythmChart), findsOneWidget);
      expect(find.byType(ConsistencyGrid), findsOneWidget);
      expect(find.text('FIVE WEEKS'), findsOneWidget);
      expect(
          find.textContaining('Up within 15 minutes of your alarm'),
          findsOneWidget);
    });

    testWidgets('an empty log says what will appear, never an empty axis',
        (t) async {
      await _pump(t, _host());
      await t.pumpAndSettle();
      expect(find.text('No mornings to chart yet'), findsOneWidget);
    });

    testWidgets('surfaces honest patterns once there is enough data',
        (t) async {
      final events = [
        for (var d = 22; d <= 26; d++) evOn(DateTime(2026, 7, d)),
      ];
      await _pump(t, _host(events: events));
      await t.pumpAndSettle();
      expect(find.text('PATTERNS'), findsOneWidget);
      expect(find.textContaining('woke on time on 100%'), findsOneWidget);
      expect(find.textContaining('not judgements'), findsOneWidget);
    });

    testWidgets('too little data keeps the patterns section hidden', (t) async {
      await _pump(t, _host(events: [evOn(DateTime(2026, 7, 26))]));
      await t.pumpAndSettle();
      expect(find.text('PATTERNS'), findsNothing);
    });
  });

  group('Progress lens', () {
    testWidgets('shows the run, its best and the freezes left', (t) async {
      await _pump(t, _host(
        events: [evOn(DateTime(2026, 7, 26))],
        streak: const StreakStats(
            current: 4, best: 9, freezesRemaining: 1, byDay: {}),
      ));
      await t.pumpAndSettle();
      await _lens(t, 'Progress');
      expect(find.text('STREAK'), findsOneWidget);
      expect(find.text('9'), findsOneWidget); // best
      expect(find.text('current'), findsOneWidget);
      expect(find.text('freeze left'), findsOneWidget);
    });

    testWidgets('badges become a rail, earned first, with what is next',
        (t) async {
      await _pump(t, _host(events: [evOn(DateTime(2026, 7, 26))]));
      await t.pumpAndSettle();
      await _lens(t, 'Progress');
      expect(find.text('BADGES'), findsOneWidget);
      expect(find.byType(MedallionRail), findsOneWidget);
      expect(find.text('First light'), findsOneWidget); // earned
      expect(find.text('1 / 8'), findsOneWidget); // one of eight
    });

    testWidgets('Alertness shows the latest score, average and honest subtext',
        (t) async {
      await _pump(t, _host(events: [
        evScore(60, order: 1),
        evScore(84, order: 2), // latest
      ]));
      await t.pumpAndSettle();
      await _lens(t, 'Progress');
      expect(find.text('ALERTNESS'), findsOneWidget);
      expect(find.text('84'), findsOneWidget);
      expect(find.text('72'), findsOneWidget); // average of 60 and 84
      expect(find.text('sharp'), findsOneWidget);
      expect(
          find.text('Your reaction speed at wake-up — sharper is more awake. '
              'Not a medical measure.'),
          findsOneWidget);
    });

    testWidgets('no scores yet shows the placeholder, not a fake zero',
        (t) async {
      await _pump(t, _host(events: [evOn(DateTime(2026, 7, 26))]));
      await t.pumpAndSettle();
      await _lens(t, 'Progress');
      expect(find.textContaining('No alertness scores yet'), findsOneWidget);
      expect(find.textContaining('Alertness (PVT)'), findsOneWidget);
      expect(find.textContaining('Not a medical measure'), findsNothing);
    });

    testWidgets('the disclaimer rides with the alertness section always',
        (t) async {
      await _pump(t, _host(events: [evScore(70, order: 1)]));
      await t.pumpAndSettle();
      await _lens(t, 'Progress');
      expect(find.textContaining('wellness insight, not a'), findsOneWidget);
    });

    testWidgets('the trend folds under Alertness once enough scores exist',
        (t) async {
      await _pump(t, _host(events: [
        evScore(45, order: 1),
        evScore(50, order: 2),
        evScore(78, order: 3),
        evScore(82, order: 4), // rising
      ]));
      await t.pumpAndSettle();
      await _lens(t, 'Progress');
      expect(find.text('ALERTNESS'), findsOneWidget);
      expect(find.text('ALERTNESS TREND'), findsNothing);
      expect(find.text('Trending up'), findsOneWidget);
      expect(find.byType(Sparkline), findsWidgets);
    });

    testWidgets('rough-night and share sit side by side as one action row',
        (t) async {
      await _pump(t, _host(events: [evOn(DateTime(2026, 7, 26))]));
      await t.pumpAndSettle();
      await _lens(t, 'Progress');
      final rough = t.getCenter(find.text('Rough night?'));
      final share = t.getCenter(find.text('Share your progress'));
      expect((rough.dy - share.dy).abs(), lessThan(30));
      expect(rough.dx, lessThan(share.dx));
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
          streakProvider.overrideWithValue(const StreakStats(
              current: 3, best: 3, freezesRemaining: 0, byDay: {})),
          // The card only needs a plain stream for display; the real repo
          // handles the tap. The repo's drift watchAll() stream would leave a
          // pending stream-close timer at teardown.
          excusedDaysProvider
              .overrideWith((ref) => Stream.value(const <DateTime>{})),
          excusedDaysRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(home: Scaffold(body: StatsScreen())),
      ));
      await t.pumpAndSettle();
      await _lens(t, 'Progress');

      expect(find.text('Rough night?'), findsOneWidget);
      await t.tap(find.byKey(const Key('rough-night-card')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('rough-today')));
      await t.pumpAndSettle();

      final days = await repo.all();
      expect(days, hasLength(1));
      expect(days.single, ExcusedDaysRepository.dayOf(DateTime.now()));
    });

    testWidgets('share affordance runs the share step on tap', (t) async {
      GlobalKey? captured;
      await _pump(t, _host(
        events: [evOn(DateTime(2026, 7, 26))],
        shareRunner: (key) async => captured = key,
      ));
      await t.pumpAndSettle();
      await _lens(t, 'Progress');
      expect(find.byKey(const Key('share-stats-card')), findsOneWidget);
      await t.tap(find.byKey(const Key('share-stats-card')));
      await t.pumpAndSettle();
      expect(captured, isNotNull);
      expect(find.textContaining("Couldn't share"), findsNothing);
    });

    testWidgets('share failure surfaces a graceful toast, never a crash',
        (t) async {
      await _pump(t, _host(
        events: [evOn(DateTime(2026, 7, 26))],
        shareRunner: (key) async => throw Exception('boom'),
      ));
      await t.pumpAndSettle();
      await _lens(t, 'Progress');
      await t.tap(find.byKey(const Key('share-stats-card')));
      await t.pumpAndSettle();
      expect(find.textContaining("Couldn't share right now"), findsOneWidget);
    });
  });

  group('Crew lens', () {
    testWidgets('signed out points at the Profile tab', (t) async {
      await _pump(t, _host());
      await t.pumpAndSettle();
      await _lens(t, 'Crew');
      expect(
          find.textContaining('Sign in from the Profile tab'), findsOneWidget);
    });

    testWidgets('signed in renders the podium and the crew score', (t) async {
      await _pumpSignedIn(t, standings: [
        _standing('fake-uid', 'me', 5, isMe: true),
        _standing('u2', 'bo', 3),
      ]);
      expect(find.text('CREW LEADERBOARD'), findsOneWidget);
      expect(find.byType(Podium), findsOneWidget);
      expect(find.text('1ST'), findsOneWidget);
      expect(find.text('CREW SCORE'), findsOneWidget);
      expect(find.textContaining('Your part:'), findsOneWidget);
    });

    testWidgets('a fourth-place crew member is a row, and opens their page',
        (t) async {
      await _pumpSignedIn(t, standings: [
        _standing('fake-uid', 'me', 9, isMe: true),
        _standing('u2', 'bo', 7),
        _standing('u3', 'cy', 5),
        _standing('u4', 'di', 3),
      ]);
      expect(find.byKey(const Key('standing-u4')), findsOneWidget);
      await t.tap(find.byKey(const Key('standing-u4')));
      await t.pumpAndSettle();
      expect(find.byType(FriendDetailScreen), findsOneWidget);
    });

    testWidgets('a podium member opens their page too', (t) async {
      await _pumpSignedIn(t, standings: [
        _standing('fake-uid', 'me', 5, isMe: true),
        _standing('u2', 'bo', 3),
      ]);
      await t.tap(find.byKey(const Key('podium-u2')));
      await t.pumpAndSettle();
      expect(find.byType(FriendDetailScreen), findsOneWidget);
    });

    testWidgets('your own row stays visible when you fall outside the shown set',
        (t) async {
      await _pumpSignedIn(t, standings: [
        for (var i = 0; i < 6; i++) _standing('u$i', 'u$i', 20 - i),
        _standing('fake-uid', 'me', 1, isMe: true),
      ]);
      expect(find.byKey(const Key('standing-fake-uid')), findsOneWidget);
      expect(find.text('You'), findsOneWidget);
    });

    testWidgets('an empty leaderboard says what to do next', (t) async {
      await _pumpSignedIn(t);
      expect(find.textContaining('add crew and start a streak'), findsOneWidget);
    });

    testWidgets('first load shows the podium skeleton, not a spinner',
        (t) async {
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
          leaderboardServiceProvider
              .overrideWithValue(_PendingLeaderboardService()),
        ],
        child: MaterialApp(home: Scaffold(body: StatsScreen(clock: _now))),
      ));
      await t.pump();
      await t.tap(find.text('Crew'));
      // Skeletons pulse forever — settle would never return. Plain frames only.
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(find.byType(RiseSkeletonCircle), findsWidgets);
      expect(find.byType(RiseSpinner), findsNothing);
    });
  });

  group('the streak-risk banner', () {
    testWidgets('appears when the run is on the line and crew exists',
        (t) async {
      await _pumpRisk(t,
          streak: _pendingToday(5),
          friends: [_member('u1', 'ada')]);
      expect(find.byKey(const Key('accountability-ping-card')), findsOneWidget);
      expect(find.text('Keep your streak alive'), findsOneWidget);
    });

    testWidgets('confirming pings every crew member via the nudge path',
        (t) async {
      final nudge = await _pumpRisk(t,
          streak: _pendingToday(5),
          friends: [_member('u1', 'ada'), _member('u2', 'bo')]);
      await t.tap(find.byKey(const Key('accountability-ping-card')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('accountability-ping-confirm')));
      await t.pumpAndSettle();
      expect(nudge.nudgeCount, 2, reason: 'one per crew member');
      expect(nudge.lastKind, NudgeKind.backup,
          reason: 'the server composes the fixed backup copy from the kind');
    });

    testWidgets('hidden when the run is not at risk', (t) async {
      await _pumpRisk(t,
          streak: StreakStats(
              current: 5,
              best: 5,
              freezesRemaining: 0,
              byDay: {
                ExcusedDaysRepository.dayOf(DateTime.now()):
                    DayOutcome.success
              }),
          friends: [_member('u1', 'ada')]);
      expect(find.byKey(const Key('accountability-ping-card')), findsNothing);
    });

    testWidgets('hidden when there is no crew to tell', (t) async {
      await _pumpRisk(t, streak: _pendingToday(5));
      expect(find.byKey(const Key('accountability-ping-card')), findsNothing);
    });
  });

  group('alertness helpers', () {
    test('averageAlertness averages non-null scores (rounded), else null', () {
      expect(
          averageAlertness(
              [evScore(80, order: 1), evScore(null, order: 2), evScore(90, order: 3)]),
          85);
      expect(averageAlertness([evScore(70, order: 1), evScore(75, order: 2)]),
          73); // 72.5 -> 73
      expect(averageAlertness(const []), isNull);
      expect(
          averageAlertness([evScore(null, order: 1), evScore(null, order: 2)]),
          isNull);
    });

    test('alertnessBand labels scores with neutral descriptors', () {
      expect(alertnessBand(80), 'sharp');
      expect(alertnessBand(95), 'sharp');
      expect(alertnessBand(50), 'steady');
      expect(alertnessBand(79), 'steady');
      expect(alertnessBand(49), 'groggy');
      expect(alertnessBand(0), 'groggy');
    });
  });
}
