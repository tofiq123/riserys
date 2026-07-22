import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/auth/auth_service.dart';
import 'package:rise/data/crew/crew_service.dart';
import 'package:rise/data/feed/feed_service.dart';
import 'package:rise/data/group/group_service.dart';
import 'package:rise/data/nudge/nudge_service.dart';
import 'package:rise/data/status/status_service.dart';
import 'package:rise/domain/crew_member.dart';
import 'package:rise/domain/crew_state.dart';
import 'package:rise/domain/crew_status.dart';
import 'package:rise/domain/feed_item.dart';
import 'package:rise/domain/group.dart';
import 'package:rise/ui/screens/activity_feed_screen.dart';
import 'package:rise/ui/screens/crew_screen.dart';
import 'package:rise/ui/screens/friend_detail_screen.dart';
import 'package:rise/ui/screens/group_detail_screen.dart';
import 'package:rise/ui/screens/voice_inbox_screen.dart';
import 'package:rise/ui/state/auth_providers.dart';
import 'package:rise/ui/state/crew_providers.dart';
import 'package:rise/ui/state/feed_providers.dart';
import 'package:rise/ui/state/group_providers.dart';
import 'package:rise/ui/state/nudge_providers.dart';
import 'package:rise/ui/state/status_providers.dart';

CrewMember _m(String id, String username) => CrewMember(
    id: id, username: username, displayName: username, avatarColor: '#7C9CF4');

FeedItem _feedItem(String id, {String username = 'ada', int streak = 6}) =>
    FeedItem(
      id: id,
      userId: 'u_$id',
      username: username,
      displayName: username,
      avatarColor: '#7C9CF4',
      wokeAt: DateTime.utc(2026, 7, 20, 7, 2),
      onTime: true,
      streak: streak,
    );

Future<FakeCrewService> _pumpSignedIn(
  WidgetTester t, {
  CrewState initial = CrewState.empty,
  List<CrewMember> directory = const [],
  Map<String, CrewStatus> statuses = const {},
  NudgeService? nudge,
  FeedService? feed,
  GroupService? groups,
}) async {
  final auth = FakeAuthService();
  await auth.signInWithGoogle();
  await auth.claimUsername('me', displayName: 'Me');
  addTearDown(auth.dispose);
  final crew = FakeCrewService(
      selfId: auth.current!.id, initial: initial, directory: directory);
  addTearDown(crew.dispose);
  final status = FakeStatusService(initial: statuses);
  addTearDown(status.dispose);

  t.view.physicalSize = const Size(2400, 8000);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.reset);

  await t.pumpWidget(ProviderScope(
    overrides: [
      authServiceProvider.overrideWithValue(auth),
      crewServiceProvider.overrideWithValue(crew),
      statusServiceProvider.overrideWithValue(status),
      if (nudge != null) nudgeServiceProvider.overrideWithValue(nudge),
      if (feed != null) feedServiceProvider.overrideWithValue(feed),
      if (groups != null) groupServiceProvider.overrideWithValue(groups),
    ],
    child: const MaterialApp(home: Scaffold(body: CrewScreen())),
  ));
  await t.pumpAndSettle();
  return crew;
}

/// A crew feed that fails its first load, then recovers — for asserting the
/// inline feed section's error card and its Retry.
class _FlakyFeedService implements FeedService {
  _FlakyFeedService(this._recovered);
  final List<FeedItem> _recovered;
  int calls = 0;

  @override
  Future<List<FeedItem>> crewFeed() async {
    calls++;
    if (calls == 1) throw Exception('feed unavailable');
    return _recovered;
  }

  @override
  Future<void> publishWake(
      {required DateTime wokeAt,
      required bool onTime,
      required int streak}) async {}
  @override
  Future<void> react(String feedId, String emoji) async {}
  @override
  Future<void> unreact(String feedId, String emoji) async {}
}

void main() {
  group('signed out', () {
    testWidgets('unconfigured build shows the hero without a dead sign-in',
        (t) async {
      await t.pumpWidget(const ProviderScope(
          child: MaterialApp(home: Scaffold(body: CrewScreen()))));
      await t.pumpAndSettle();
      expect(find.text('Wake up together'), findsOneWidget);
      expect(find.text('Sign in with Google'), findsNothing);
      expect(find.textContaining('coming soon'), findsOneWidget);
    });

    testWidgets('configured build offers sign-in right on the hero',
        (t) async {
      final auth = FakeAuthService();
      addTearDown(auth.dispose);
      await t.pumpWidget(ProviderScope(
        overrides: [authServiceProvider.overrideWithValue(auth)],
        child: const MaterialApp(home: Scaffold(body: CrewScreen())),
      ));
      await t.pumpAndSettle();
      expect(find.text('Wake up together'), findsOneWidget);
      await t.tap(find.text('Sign in with Google'));
      await t.pumpAndSettle();
      expect(auth.current, isNotNull);
      // Signed in now — the dashboard (here: its empty-crew hero) appears.
      expect(find.text('Mornings are better with a crew'), findsOneWidget);
    });
  });

  group('empty crew', () {
    testWidgets('shows the hero with both next steps', (t) async {
      await _pumpSignedIn(t);
      expect(find.text('Mornings are better with a crew'), findsOneWidget);
      expect(find.text('Add your first friend'), findsOneWidget);
      // In the hero — and again as a dashed card on the empty Groups strip.
      expect(find.text('Join a group'), findsWidgets);
    });
  });

  group('adding friends (the + sheet)', () {
    testWidgets('find + add sends a friend request', (t) async {
      final crew = await _pumpSignedIn(t, directory: [_m('u1', 'ada')]);
      await t.tap(find.byKey(const Key('crew-add-button')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('crew-search-field')), 'ada');
      await t.tap(find.text('Find'));
      await t.pumpAndSettle();
      await t.tap(find.text('Add'));
      await t.pumpAndSettle();
      expect(crew.current.outgoing.map((m) => m.id), ['u1']);
    });

    testWidgets('searching an unknown handle shows a not-found message',
        (t) async {
      await _pumpSignedIn(t);
      await t.tap(find.byKey(const Key('crew-add-button')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('crew-search-field')), 'ghost');
      await t.tap(find.text('Find'));
      await t.pumpAndSettle();
      expect(find.textContaining('No one with the handle'), findsOneWidget);
    });

    testWidgets('sent requests appear in the sheet and can be cancelled',
        (t) async {
      final crew =
          await _pumpSignedIn(t, initial: CrewState(outgoing: [_m('u1', 'ada')]));
      await t.tap(find.byKey(const Key('crew-add-button')));
      await t.pumpAndSettle();
      expect(find.text('WAITING ON THEM'), findsOneWidget);
      expect(find.text('@ada'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(crew.current.outgoing, isEmpty);
    });
  });

  group('requests banner', () {
    testWidgets('accepting an incoming request moves them to your crew',
        (t) async {
      final crew =
          await _pumpSignedIn(t, initial: CrewState(incoming: [_m('u1', 'ada')]));
      expect(find.text('ada wants to join your crew'), findsOneWidget);
      await t.tap(find.byKey(const Key('crew-requests-banner')));
      await t.pumpAndSettle();
      await t.tap(find.text('Accept'));
      await t.pumpAndSettle();
      expect(crew.current.friends.map((m) => m.id), ['u1']);
      expect(crew.current.incoming, isEmpty);
      // Last request handled -> the sheet closed and the banner is gone.
      expect(find.byKey(const Key('crew-requests-banner')), findsNothing);
    });

    testWidgets('declining an incoming request removes it', (t) async {
      final crew =
          await _pumpSignedIn(t, initial: CrewState(incoming: [_m('u1', 'ada')]));
      await t.tap(find.byKey(const Key('crew-requests-banner')));
      await t.pumpAndSettle();
      await t.tap(find.text('Decline'));
      await t.pumpAndSettle();
      expect(crew.current.incoming, isEmpty);
      expect(crew.current.friends, isEmpty);
    });

    testWidgets('several requests read as a count', (t) async {
      await _pumpSignedIn(t,
          initial: CrewState(incoming: [_m('u1', 'ada'), _m('u2', 'bo')]));
      expect(find.text('2 people want to join your crew'), findsOneWidget);
    });
  });

  group('the This-morning strip', () {
    testWidgets('a member chip shows their live status word', (t) async {
      await _pumpSignedIn(t,
          initial: CrewState(friends: [_m('u1', 'ada')]),
          statuses: {'u1': CrewStatus.waking});
      expect(find.text('Waking'), findsOneWidget);
    });

    testWidgets('no status degrades to the quiet word', (t) async {
      await _pumpSignedIn(t, initial: CrewState(friends: [_m('u1', 'ada')]));
      expect(find.text('Quiet'), findsOneWidget);
      expect(find.text('Waking'), findsNothing);
    });

    testWidgets('waking members sort ahead of sleeping ones', (t) async {
      await _pumpSignedIn(t,
          initial: CrewState(friends: [_m('u1', 'ada'), _m('u2', 'bo')]),
          statuses: {'u1': CrewStatus.asleep, 'u2': CrewStatus.waking});
      final adaX = t.getTopLeft(find.byKey(const Key('crew-chip-u1'))).dx;
      final boX = t.getTopLeft(find.byKey(const Key('crew-chip-u2'))).dx;
      expect(boX, lessThan(adaX));
    });

    testWidgets('tapping a chip opens the friend detail page', (t) async {
      await _pumpSignedIn(t, initial: CrewState(friends: [_m('u1', 'ada')]));
      await t.tap(find.byKey(const Key('crew-chip-u1')));
      await t.pumpAndSettle();
      expect(find.byType(FriendDetailScreen), findsOneWidget);
    });

    testWidgets('nudging is reachable through the friend detail page',
        (t) async {
      final nudge = FakeNudgeService();
      await _pumpSignedIn(t,
          initial: CrewState(friends: [_m('u1', 'ada')]), nudge: nudge);
      await t.tap(find.byKey(const Key('crew-chip-u1')));
      await t.pumpAndSettle();
      await t.tap(find.text('Nudge'));
      await t.pumpAndSettle();
      expect(nudge.lastNudged, 'u1');
    });

    testWidgets('removing is reachable through the detail overflow, confirmed',
        (t) async {
      final crew =
          await _pumpSignedIn(t, initial: CrewState(friends: [_m('u1', 'ada')]));
      await t.tap(find.byKey(const Key('crew-chip-u1')));
      await t.pumpAndSettle();
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
  });

  group('cheer them on (inline feed)', () {
    testWidgets('renders the latest wakes and See all opens the full feed',
        (t) async {
      await _pumpSignedIn(t,
          initial: CrewState(friends: [_m('u1', 'ada')]),
          feed: FakeFeedService(initial: [_feedItem('f1')], selfId: 'me'));
      expect(find.textContaining('woke on time'), findsOneWidget);
      await t.tap(find.byKey(const Key('crew-feed-see-all')));
      await t.pumpAndSettle();
      expect(find.byType(ActivityFeedScreen), findsOneWidget);
    });

    testWidgets('an empty feed shows the quiet card, never dead space',
        (t) async {
      await _pumpSignedIn(t, initial: CrewState(friends: [_m('u1', 'ada')]));
      expect(find.textContaining('Quiet for now'), findsOneWidget);
    });

    testWidgets(
        'a feed error shows the error card with Retry, not the quiet card',
        (t) async {
      final feed = _FlakyFeedService([_feedItem('f1')]);
      await _pumpSignedIn(t,
          initial: CrewState(friends: [_m('u1', 'ada')]), feed: feed);
      // The error card (with Retry) — never the "quiet" empty card, which would
      // make a network failure look identical to "nothing has happened yet".
      expect(find.text('Retry'), findsOneWidget);
      expect(find.textContaining("Couldn't load"), findsOneWidget);
      expect(find.textContaining('Quiet for now'), findsNothing);
      // Retry re-runs the load; the feed recovers and the wake shows.
      await t.tap(find.text('Retry'));
      await t.pumpAndSettle();
      expect(find.textContaining('woke on time'), findsOneWidget);
      expect(feed.calls, 2);
    });
  });

  group('header actions', () {
    testWidgets('the voice-inbox icon opens the Voice inbox', (t) async {
      await _pumpSignedIn(t);
      await t.tap(find.byKey(const Key('crew-voice-inbox')));
      await t.pumpAndSettle();
      expect(find.byType(VoiceInboxScreen), findsOneWidget);
    });
  });

  group('groups strip', () {
    testWidgets('shows my groups and opens a group page', (t) async {
      await _pumpSignedIn(t,
          groups: FakeGroupService(groups: const [
            Group(
                id: 'g1',
                name: 'Early Risers',
                inviteCode: 'RISE42',
                ownerId: 'me',
                role: 'owner'),
          ]));
      expect(find.text('Early Risers'), findsOneWidget);
      await t.tap(find.byKey(const Key('group-card-g1')));
      await t.pumpAndSettle();
      expect(find.byType(GroupDetailScreen), findsOneWidget);
    });
  });
}
