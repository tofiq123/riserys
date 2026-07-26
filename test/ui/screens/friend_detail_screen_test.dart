import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/crew/crew_service.dart';
import 'package:rise/data/feed/feed_service.dart';
import 'package:rise/data/leaderboard/leaderboard_service.dart';
import 'package:rise/data/nudge/nudge_service.dart';
import 'package:rise/data/status/status_service.dart';
import 'package:rise/domain/crew_member.dart';
import 'package:rise/domain/crew_standing.dart';
import 'package:rise/domain/crew_state.dart';
import 'package:rise/domain/crew_status.dart';
import 'package:rise/domain/feed_item.dart';
import 'package:rise/domain/wake_stats.dart';
import 'package:rise/ui/screens/friend_detail_screen.dart';
import 'package:rise/ui/state/crew_providers.dart';
import 'package:rise/ui/state/feed_providers.dart';
import 'package:rise/ui/state/leaderboard_providers.dart';
import 'package:rise/ui/state/nudge_providers.dart';
import 'package:rise/ui/state/status_providers.dart';

const _ada = CrewMember(
    id: 'u1', username: 'ada', displayName: 'Ada', avatarColor: '#7C9CF4');

CrewStanding _standing(String id,
        {int current = 0,
        int best = 0,
        int total = 0,
        int onTime = 0,
        bool isMe = false}) =>
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

/// A wake by [userId] earlier today, so it lands in the Today card.
FeedItem _wokeToday(String userId,
    {bool onTime = true,
    int streak = 12,
    List<FeedReaction> react = const []}) {
  final now = DateTime.now();
  return FeedItem(
    id: 'f_$userId',
    userId: userId,
    username: userId,
    displayName: userId,
    avatarColor: '#7C9CF4',
    wokeAt: DateTime(now.year, now.month, now.day, 5, 42),
    onTime: onTime,
    streak: streak,
    reactions: react,
  );
}

Future<(FakeCrewService, FakeNudgeService)> _pump(
  WidgetTester t, {
  Map<String, CrewStatus> statuses = const {},
  List<CrewStanding> standings = const [],
  FeedService? feed,
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
      if (feed != null) feedServiceProvider.overrideWithValue(feed),
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

  testWidgets('unknown status degrades to a gentle placeholder', (t) async {
    await _pump(t);
    expect(find.text('No status right now'), findsOneWidget);
  });

  testWidgets('renders streak, on-time % and best as stat tiles', (t) async {
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

  testWidgets('the voice-clip action is offered as a secondary', (t) async {
    await _pump(t);
    expect(find.text('Send a voice clip'), findsOneWidget);
  });

  testWidgets('remove hides in the overflow and still confirms first',
      (t) async {
    final (crew, _) = await _pump(t);
    // Not on the main surface anymore.
    expect(find.text('Remove'), findsNothing);
    await t.tap(find.byKey(const Key('friend-overflow')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('friend-remove-action')));
    await t.pumpAndSettle();
    expect(crew.current.friends, isNotEmpty,
        reason: 'not removed until confirmed');
    await t.tap(find.byKey(const Key('confirm-dialog-confirm')));
    await t.pumpAndSettle();
    expect(crew.current.friends, isEmpty);
  });

  group('today leads the page', () {
    testWidgets('their wake, the run it landed, and all three actions',
        (t) async {
      await _pump(t,
          statuses: {'u1': CrewStatus.awake},
          feed: FakeFeedService(initial: [
            _wokeToday('u1', react: const [
              FeedReaction(emoji: '🔥', count: 3, reactedByMe: false)
            ])
          ]));
      expect(find.byKey(const Key('friend-today')), findsOneWidget);
      expect(find.text('5:42 AM'), findsOneWidget);
      expect(find.text('on time'), findsOneWidget);
      expect(find.text('🔥12'), findsOneWidget);
      expect(find.textContaining('Your crew left 🔥3'), findsOneWidget);
      expect(find.byKey(const Key('friend-cheer')), findsOneWidget);
      expect(find.byKey(const Key('friend-nudge')), findsOneWidget);
      expect(find.byKey(const Key('friend-voice')), findsOneWidget);
    });

    testWidgets('Today sits above their stats, which sit above You two',
        (t) async {
      await _pump(t,
          standings: [
            _standing('u1', current: 5, best: 9, total: 10, onTime: 8),
            _standing('me', current: 2, isMe: true),
          ],
          feed: FakeFeedService(initial: [_wokeToday('u1')]));
      final today = t.getTopLeft(find.byKey(const Key('friend-today'))).dy;
      final mornings = t.getTopLeft(find.text('THEIR MORNINGS')).dy;
      final youTwo = t.getTopLeft(find.text('YOU TWO')).dy;
      expect(today, lessThan(mornings));
      expect(mornings, lessThan(youTwo));
    });

    testWidgets('cheering records the reaction', (t) async {
      final feed = FakeFeedService(initial: [_wokeToday('u1')]);
      await _pump(t, feed: feed);
      await t.tap(find.byKey(const Key('friend-cheer')));
      await t.pumpAndSettle();
      final items = await feed.crewFeed();
      expect(items.single.reactionFor('🔥').count, 1);
    });

    testWidgets('a friend mid-mission gets the live treatment', (t) async {
      await _pump(t, statuses: {'u1': CrewStatus.waking});
      expect(find.byKey(const Key('friend-today-waking')), findsOneWidget);
      expect(find.text("Ada's alarm is going."), findsOneWidget);
      expect(find.byKey(const Key('friend-nudge')), findsOneWidget);
      // Nothing to cheer until the wake lands.
      expect(find.byKey(const Key('friend-cheer')), findsNothing);
    });

    testWidgets('no wake yet says so rather than showing an empty card',
        (t) async {
      await _pump(t, statuses: {'u1': CrewStatus.asleep});
      expect(find.text('No wake logged yet.'), findsOneWidget);
      expect(find.byKey(const Key('friend-cheer')), findsNothing);
      expect(find.byKey(const Key('friend-nudge')), findsOneWidget);
    });

    testWidgets('a not-on-time wake reads as "woke up", never as a failure',
        (t) async {
      await _pump(t,
          feed: FakeFeedService(
              initial: [_wokeToday('u1', onTime: false)]));
      expect(find.text('woke up'), findsOneWidget);
      expect(find.text('on time'), findsNothing);
    });
  });
}
