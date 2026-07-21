import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/auth/auth_service.dart';
import 'package:rise/data/feed/feed_service.dart';
import 'package:rise/domain/feed_item.dart';
import 'package:rise/ui/screens/activity_feed_screen.dart';
import 'package:rise/ui/state/auth_providers.dart';
import 'package:rise/ui/state/feed_providers.dart';

FeedItem _item(
  String id, {
  String username = 'ada',
  bool isMe = false,
  int streak = 6,
  List<FeedReaction> reactions = const [],
}) =>
    FeedItem(
      id: id,
      userId: 'u_$id',
      username: username,
      displayName: username,
      avatarColor: '#7C9CF4',
      wokeAt: DateTime.utc(2026, 7, 20, 7, 2),
      onTime: true,
      streak: streak,
      isMe: isMe,
      reactions: reactions,
    );

Future<FakeFeedService> _pumpSignedIn(
  WidgetTester t, {
  List<FeedItem> items = const [],
}) async {
  final auth = FakeAuthService();
  await auth.signInWithGoogle();
  await auth.claimUsername('me', displayName: 'Me');
  addTearDown(auth.dispose);
  final feed = FakeFeedService(initial: items, selfId: auth.current!.id);

  t.view.physicalSize = const Size(1400, 3000);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.reset);

  await t.pumpWidget(ProviderScope(
    overrides: [
      authServiceProvider.overrideWithValue(auth),
      feedServiceProvider.overrideWithValue(feed),
    ],
    child: const MaterialApp(home: ActivityFeedScreen()),
  ));
  await t.pumpAndSettle();
  return feed;
}

void main() {
  testWidgets('signed out shows the sign-in prompt', (t) async {
    await t.pumpWidget(const ProviderScope(
        child: MaterialApp(home: ActivityFeedScreen())));
    await t.pumpAndSettle();
    expect(find.textContaining('Sign in from the Profile tab'), findsOneWidget);
  });

  testWidgets('empty feed shows the invite-friends empty state', (t) async {
    await _pumpSignedIn(t);
    expect(find.textContaining('No crew activity yet'), findsOneWidget);
    expect(find.textContaining('cheer each other on'), findsOneWidget);
  });

  testWidgets('renders a crew member\'s wake with the reaction palette',
      (t) async {
    await _pumpSignedIn(t, items: [_item('f1')]);
    expect(find.textContaining('woke on time'), findsOneWidget);
    expect(find.textContaining('6-day streak'), findsOneWidget);
    // The four palette chips are present.
    for (final e in kFeedReactionEmojis) {
      expect(find.byKey(Key('reaction-f1-$e')), findsOneWidget);
    }
  });

  testWidgets('own wake reads "You woke on time"', (t) async {
    await _pumpSignedIn(t, items: [_item('f1', isMe: true)]);
    expect(find.textContaining('You woke on time'), findsOneWidget);
  });

  testWidgets('tapping a reaction adds it and shows the count', (t) async {
    final feed = await _pumpSignedIn(t, items: [_item('f1')]);
    await t.tap(find.byKey(const Key('reaction-f1-🔥')));
    await t.pumpAndSettle();
    // Service recorded my reaction.
    final item = (await feed.crewFeed()).single;
    expect(item.reactionFor('🔥').count, 1);
    expect(item.reactionFor('🔥').reactedByMe, isTrue);
    // And the count is now shown on the chip.
    final chip = find.byKey(const Key('reaction-f1-🔥'));
    expect(find.descendant(of: chip, matching: find.text('1')), findsOneWidget);
  });

  testWidgets('tapping an already-reacted emoji removes it', (t) async {
    final feed = await _pumpSignedIn(t, items: [
      _item('f1', reactions: const [
        FeedReaction(emoji: '🔥', count: 1, reactedByMe: true),
      ]),
    ]);
    await t.tap(find.byKey(const Key('reaction-f1-🔥')));
    await t.pumpAndSettle();
    expect((await feed.crewFeed()).single.reactionFor('🔥').count, 0);
  });
}
