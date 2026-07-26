import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/auth/auth_service.dart';
import 'package:rise/domain/rise_account.dart';
import 'package:rise/ui/components/morning_line_view.dart';
import 'package:rise/ui/components/rise_skeleton.dart';
import 'package:rise/ui/components/rise_spinner.dart';
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

/// A wake by [userId] at a LOCAL time on the pinned test day, so it lands on
/// the Morning Line (only today's wakes count as up).
FeedItem _feedItemAt(String id, String userId, int hour, int minute,
        {bool onTime = true, int streak = 6}) =>
    FeedItem(
      id: id,
      userId: userId,
      username: userId,
      displayName: userId,
      avatarColor: '#7C9CF4',
      wokeAt: DateTime(2026, 7, 26, hour, minute),
      onTime: onTime,
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
  DateTime? clock,
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
    // Pinned to mid-window unless a test asks otherwise, so a suite run at
    // 22:00 does not silently assert against the Tonight screen.
    child: MaterialApp(
        home: Scaffold(
            body: CrewScreen(clock: clock ?? _midWindow))),
  ));
  await t.pumpAndSettle();
  return crew;
}

/// 06:12 on Sunday 26 July 2026 — the wake window, three hours before it wraps.
final _midWindow = DateTime(2026, 7, 26, 6, 12);

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

/// Auth whose account() never emits: the "session restored, profile still
/// loading" window. The UI must show a neutral skeleton — never sign-in.
class _RestoringAuthService implements AuthService {
  final StreamController<RiseAccount?> _controller =
      StreamController<RiseAccount?>.broadcast();

  @override
  Stream<RiseAccount?> account() => _controller.stream;

  @override
  RiseAccount? get current => null;

  @override
  Future<void> signInWithGoogle() async {}
  @override
  Future<bool> isUsernameAvailable(String username) async => true;
  @override
  Future<void> claimUsername(String username,
      {required String displayName}) async {}
  @override
  Future<void> signOut() async {}
  @override
  Future<void> deleteAccount() async {}
}

/// Crew stream that never emits — the first-load window.
class _PendingCrewService extends FakeCrewService {
  @override
  Stream<CrewState> watch() => const Stream.empty(broadcast: true);
}

/// Feed whose fetch never completes — the first-load window.
class _PendingFeedService extends FakeFeedService {
  @override
  Future<List<FeedItem>> crewFeed() => Completer<List<FeedItem>>().future;
}

void main() {
  group('loading truth', () {
    testWidgets('restoring auth shows a skeleton — never the sign-in hero',
        (t) async {
      final auth = _RestoringAuthService();
      await t.pumpWidget(ProviderScope(
        overrides: [authServiceProvider.overrideWithValue(auth)],
        child: const MaterialApp(home: Scaffold(body: CrewScreen())),
      ));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(find.text('Continue with Google'), findsNothing);
      expect(find.textContaining('Nobody wakes'), findsNothing);
      expect(find.byType(RiseSkeletonCircle), findsWidgets);
    });

    testWidgets('crew still loading shows skeleton chips, not the empty hero',
        (t) async {
      final auth = FakeAuthService();
      await auth.signInWithGoogle();
      await auth.claimUsername('me', displayName: 'Me');
      addTearDown(auth.dispose);
      await t.pumpWidget(ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(auth),
          crewServiceProvider.overrideWithValue(_PendingCrewService()),
          feedServiceProvider.overrideWithValue(_PendingFeedService()),
        ],
        child: const MaterialApp(home: Scaffold(body: CrewScreen())),
      ));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(find.text('This is where your crew shows up.'), findsNothing);
      expect(find.byType(RiseSkeletonCircle), findsWidgets);
      // No indeterminate spinners anywhere on content load.
      expect(find.byType(RiseSpinner), findsNothing);
    });

    testWidgets('signed in dashboard offers pull-to-refresh', (t) async {
      await _pumpSignedIn(t);
      expect(find.byType(RefreshIndicator), findsOneWidget);
    });

    testWidgets('the restoring skeleton fits a narrow (360dp) phone',
        (t) async {
      // 360dp is the most common Android width; a fixed-width skeleton row
      // overflows here and throws in debug. Regression guard.
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.reset);
      final auth = _RestoringAuthService();
      await t.pumpWidget(ProviderScope(
        overrides: [authServiceProvider.overrideWithValue(auth)],
        child: const MaterialApp(home: Scaffold(body: CrewScreen())),
      ));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(t.takeException(), isNull);
      expect(find.byType(RiseSkeletonCircle), findsWidgets);
    });

    testWidgets('pull-to-refresh reloads the crew itself, not just the feed',
        (t) async {
      final crew = await _pumpSignedIn(t);
      // The arm threshold scales with viewport height (25%); the tall test
      // viewport needs a correspondingly long pull.
      await t.drag(find.byType(ListView).first, const Offset(0, 900));
      await t.pump(); // start the indicator
      await t.pump(const Duration(seconds: 1)); // run onRefresh
      await t.pumpAndSettle();
      expect(crew.reloads, greaterThan(0),
          reason: 'the gesture must refresh the This-morning strip and '
              'requests banner too');
    });
  });

  group('signed out', () {
    testWidgets('unconfigured build shows the hero without a dead sign-in',
        (t) async {
      await t.pumpWidget(const ProviderScope(
          child: MaterialApp(home: Scaffold(body: CrewScreen()))));
      await t.pumpAndSettle();
      expect(find.textContaining('Nobody wakes'), findsOneWidget);
      expect(find.text('Continue with Google'), findsNothing);
      expect(find.textContaining('coming soon'), findsOneWidget);
    });

    testWidgets('configured build offers sign-in right on the hero',
        (t) async {
      final auth = FakeAuthService();
      addTearDown(auth.dispose);
      await t.pumpWidget(ProviderScope(
        overrides: [authServiceProvider.overrideWithValue(auth)],
        child: MaterialApp(
            home: Scaffold(body: CrewScreen(clock: _midWindow))),
      ));
      await t.pumpAndSettle();
      expect(find.textContaining('Nobody wakes'), findsOneWidget);
      await t.tap(find.text('Continue with Google'));
      await t.pumpAndSettle();
      expect(auth.current, isNotNull);
      // Signed in now — the line appears, with the invitation on it.
      expect(find.text('This is where your crew shows up.'), findsOneWidget);
    });

    testWidgets('shows the shape of the thing, labelled as an example',
        (t) async {
      await t.pumpWidget(const ProviderScope(
          child: MaterialApp(home: Scaffold(body: CrewScreen()))));
      await t.pumpAndSettle();
      expect(find.text('EXAMPLE'), findsOneWidget);
      expect(find.text('Two up, one waking, one still under.'), findsOneWidget);
    });
  });

  group('empty crew', () {
    testWidgets('the line renders with you on it and the invitation below',
        (t) async {
      await _pumpSignedIn(t);
      // Your own row is on the line, so the empty state teaches the component.
      expect(find.byKey(const Key('line-row-fake-uid')), findsOneWidget);
      expect(find.text('You'), findsOneWidget);
      expect(find.text('This is where your crew shows up.'), findsOneWidget);
      expect(find.byKey(const Key('crew-add-first-friend')), findsOneWidget);
      expect(find.byKey(const Key('crew-join-group')), findsOneWidget);
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

  group('the Morning Line', () {
    testWidgets('someone still under the marker shows their live status',
        (t) async {
      await _pumpSignedIn(t,
          initial: CrewState(friends: [_m('u1', 'ada')]),
          statuses: {'u1': CrewStatus.waking});
      expect(find.text('waking'), findsOneWidget);
    });

    testWidgets('no status degrades to the quiet word', (t) async {
      await _pumpSignedIn(t, initial: CrewState(friends: [_m('u1', 'ada')]));
      expect(find.text('quiet'), findsWidgets);
      expect(find.text('waking'), findsNothing);
    });

    testWidgets('waking members sort above sleeping ones on the line',
        (t) async {
      await _pumpSignedIn(t,
          initial: CrewState(friends: [_m('u1', 'ada'), _m('u2', 'bo')]),
          statuses: {'u1': CrewStatus.asleep, 'u2': CrewStatus.waking});
      final adaY = t.getTopLeft(find.byKey(const Key('line-row-u1'))).dy;
      final boY = t.getTopLeft(find.byKey(const Key('line-row-u2'))).dy;
      expect(boY, lessThan(adaY),
          reason: 'the person you can cheer right now comes first');
    });

    testWidgets('a wake sits above the marker at the minute it happened',
        (t) async {
      await _pumpSignedIn(t,
          initial: CrewState(friends: [_m('u1', 'ada'), _m('u2', 'bo')]),
          statuses: {'u2': CrewStatus.asleep},
          feed: FakeFeedService(
              initial: [_feedItemAt('f1', 'u1', 5, 42)], selfId: 'me'));
      expect(find.text('5:42 AM'), findsOneWidget);
      expect(find.text('on time'), findsOneWidget);

      final markerY = t.getTopLeft(find.byType(NowMarker)).dy;
      expect(t.getTopLeft(find.byKey(const Key('line-row-u1'))).dy,
          lessThan(markerY));
      expect(t.getTopLeft(find.byKey(const Key('line-row-u2'))).dy,
          greaterThan(markerY));
    });

    testWidgets('the hero counts what is true right now', (t) async {
      await _pumpSignedIn(t,
          initial: CrewState(friends: [_m('u1', 'ada'), _m('u2', 'bo')]),
          feed: FakeFeedService(
              initial: [_feedItemAt('f1', 'u1', 5, 42)], selfId: 'me'));
      expect(find.byKey(const Key('crew-hero-window')), findsOneWidget);
      expect(find.text('Wake window'), findsOneWidget);
      // You plus two friends; one of the three is up.
      expect(find.text('of 3 up'), findsOneWidget);
      expect(find.textContaining('was first, 5:42 AM'), findsOneWidget);
    });

    testWidgets('after the window the page becomes a record, with no marker',
        (t) async {
      await _pumpSignedIn(t,
          clock: DateTime(2026, 7, 26, 11),
          initial: CrewState(friends: [_m('u1', 'ada'), _m('u2', 'bo')]),
          feed: FakeFeedService(
              initial: [_feedItemAt('f1', 'u1', 5, 42)], selfId: 'me'));
      expect(find.text("Today's mornings"), findsOneWidget);
      expect(find.byKey(const Key('crew-hero-wrapped')), findsOneWidget);
      expect(find.byType(NowMarker), findsNothing);
      expect(find.text('no wake logged'), findsWidgets);
    });

    testWidgets('at night the headline is your own alarm', (t) async {
      await _pumpSignedIn(t,
          clock: DateTime(2026, 7, 26, 22, 30),
          initial: CrewState(friends: [_m('u1', 'ada')]));
      expect(find.text('Tonight'), findsOneWidget);
      expect(find.byKey(const Key('crew-hero-tonight')), findsOneWidget);
      expect(find.byType(NowMarker), findsNothing);
    });

    testWidgets('tapping a row opens the friend detail page', (t) async {
      await _pumpSignedIn(t, initial: CrewState(friends: [_m('u1', 'ada')]));
      await t.tap(find.byKey(const Key('line-row-u1')));
      await t.pumpAndSettle();
      expect(find.byType(FriendDetailScreen), findsOneWidget);
    });

    testWidgets('nudging is reachable through the friend detail page',
        (t) async {
      final nudge = FakeNudgeService();
      await _pumpSignedIn(t,
          initial: CrewState(friends: [_m('u1', 'ada')]), nudge: nudge);
      await t.tap(find.byKey(const Key('line-row-u1')));
      await t.pumpAndSettle();
      await t.tap(find.text('Nudge'));
      await t.pumpAndSettle();
      expect(nudge.lastNudged, 'u1');
    });

    testWidgets('removing is reachable through the detail overflow, confirmed',
        (t) async {
      final crew =
          await _pumpSignedIn(t, initial: CrewState(friends: [_m('u1', 'ada')]));
      await t.tap(find.byKey(const Key('line-row-u1')));
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

  group('cheering', () {
    testWidgets('See all opens the full activity screen', (t) async {
      await _pumpSignedIn(t,
          initial: CrewState(friends: [_m('u1', 'ada')]),
          feed: FakeFeedService(initial: [_feedItem('f1')], selfId: 'me'));
      await t.tap(find.byKey(const Key('line-see-all')));
      await t.pumpAndSettle();
      expect(find.byType(ActivityFeedScreen), findsOneWidget);
    });

    testWidgets('Cheer opens the palette and records the reaction', (t) async {
      final feed = FakeFeedService(
          initial: [_feedItemAt('f1', 'u1', 5, 42)], selfId: 'me');
      await _pumpSignedIn(t,
          initial: CrewState(friends: [_m('u1', 'ada')]), feed: feed);
      await t.tap(find.byKey(const Key('line-cheer-u1')));
      await t.pump();
      await t.tap(find.byKey(const Key('line-cheer-u1-🔥')));
      await t.pumpAndSettle();
      final items = await feed.crewFeed();
      expect(items.single.reactionFor('🔥').count, 1);
      expect(items.single.reactionFor('🔥').reactedByMe, isTrue);
      expect(find.text('🔥 1'), findsOneWidget);
    });

    testWidgets('a feed failure says what is missing and offers a retry',
        (t) async {
      final feed = _FlakyFeedService([_feedItemAt('f1', 'u1', 5, 42)]);
      await _pumpSignedIn(t,
          initial: CrewState(friends: [_m('u1', 'ada')]),
          statuses: {'u1': CrewStatus.asleep},
          feed: feed);
      // Never silence: a network failure must not look identical to
      // "nothing has happened yet".
      expect(find.text('Retry'), findsOneWidget);
      expect(find.textContaining("Couldn't load"), findsOneWidget);
      // The line still renders from live status, so the screen stays useful.
      expect(find.byKey(const Key('line-row-u1')), findsOneWidget);
      expect(find.text('asleep'), findsOneWidget);

      await t.tap(find.text('Retry'));
      await t.pumpAndSettle();
      expect(find.text('5:42 AM'), findsOneWidget);
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
