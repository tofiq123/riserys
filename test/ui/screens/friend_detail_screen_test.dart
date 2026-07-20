import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/crew/crew_service.dart';
import 'package:rise/data/leaderboard/leaderboard_service.dart';
import 'package:rise/data/nudge/nudge_service.dart';
import 'package:rise/data/status/status_service.dart';
import 'package:rise/domain/crew_member.dart';
import 'package:rise/domain/crew_standing.dart';
import 'package:rise/domain/crew_state.dart';
import 'package:rise/domain/crew_status.dart';
import 'package:rise/domain/wake_stats.dart';
import 'package:rise/ui/screens/friend_detail_screen.dart';
import 'package:rise/ui/state/crew_providers.dart';
import 'package:rise/ui/state/leaderboard_providers.dart';
import 'package:rise/ui/state/nudge_providers.dart';
import 'package:rise/ui/state/status_providers.dart';

const _ada = CrewMember(
    id: 'u1', username: 'ada', displayName: 'Ada', avatarColor: '#7C9CF4');

CrewStanding _standing(String id,
        {int current = 0, int best = 0, int total = 0, int onTime = 0, bool isMe = false}) =>
    CrewStanding(
      id: id,
      username: id,
      displayName: id,
      avatarColor: '#7C9CF4',
      stats: WakeStats(
          currentStreak: current,
          bestStreak: best,
          totalWakes: total,
          onTimeCount: onTime),
      isMe: isMe,
    );

Future<(FakeCrewService, FakeNudgeService)> _pump(
  WidgetTester t, {
  Map<String, CrewStatus> statuses = const {},
  List<CrewStanding> standings = const [],
}) async {
  final crew = FakeCrewService(initial: CrewState(friends: [_ada]));
  addTearDown(crew.dispose);
  final status = FakeStatusService(initial: statuses);
  addTearDown(status.dispose);
  final nudge = FakeNudgeService();

  t.view.physicalSize = const Size(1400, 3200);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.reset);

  await t.pumpWidget(ProviderScope(
    overrides: [
      crewServiceProvider.overrideWithValue(crew),
      statusServiceProvider.overrideWithValue(status),
      nudgeServiceProvider.overrideWithValue(nudge),
      leaderboardServiceProvider
          .overrideWithValue(FakeLeaderboardService(standings: standings)),
    ],
    child: const MaterialApp(home: FriendDetailScreen(member: _ada)),
  ));
  await t.pumpAndSettle();
  return (crew, nudge);
}

void main() {
  testWidgets('shows the member identity and live status', (t) async {
    await _pump(t, statuses: {'u1': CrewStatus.awake});
    expect(find.text('Ada'), findsWidgets);
    expect(find.text('@ada'), findsWidgets);
    expect(find.text('Up and about'), findsOneWidget);
  });

  testWidgets('unknown status degrades to a placeholder', (t) async {
    await _pump(t);
    expect(find.text('Status unavailable'), findsOneWidget);
  });

  testWidgets('renders their streak and on-time % from the leaderboard',
      (t) async {
    await _pump(t, standings: [
      _standing('u1', current: 5, best: 9, total: 10, onTime: 8),
    ]);
    expect(find.text('5'), findsOneWidget); // current streak
    expect(find.text('9'), findsOneWidget); // best
    expect(find.text('80%'), findsOneWidget); // on-time rate
  });

  testWidgets('shows a mutual comparison when both standings are present',
      (t) async {
    await _pump(t, standings: [
      _standing('u1', current: 5, best: 9, total: 10, onTime: 8),
      _standing('me', current: 3, isMe: true),
    ]);
    expect(find.textContaining('ahead by'), findsOneWidget);
  });

  testWidgets('degrades gracefully when the member is not on the leaderboard',
      (t) async {
    await _pump(t, standings: [_standing('me', current: 3, isMe: true)]);
    expect(find.text('No stats to show yet'), findsOneWidget);
  });

  testWidgets('Nudge action calls the nudge service', (t) async {
    final (_, nudge) = await _pump(t);
    await t.tap(find.text('Nudge'));
    await t.pumpAndSettle();
    expect(nudge.lastNudged, 'u1');
  });

  testWidgets('Remove action removes the friend', (t) async {
    final (crew, _) = await _pump(t);
    await t.tap(find.text('Remove'));
    await t.pumpAndSettle();
    expect(crew.current.friends, isEmpty);
  });
}
