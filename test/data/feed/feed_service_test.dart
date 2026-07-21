import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/feed/feed_service.dart';
import 'package:rise/domain/feed_item.dart';

FeedItem _item(String id, {List<FeedReaction> reactions = const []}) => FeedItem(
      id: id,
      userId: 'u_$id',
      username: id,
      displayName: id,
      avatarColor: '#7C9CF4',
      wokeAt: DateTime.utc(2026, 7, 20, 7),
      onTime: true,
      streak: 3,
      reactions: reactions,
    );

void main() {
  group('FakeFeedService', () {
    test('crewFeed returns the seeded items', () async {
      final svc = FakeFeedService(initial: [_item('a'), _item('b')]);
      final feed = await svc.crewFeed();
      expect(feed.map((i) => i.id), ['a', 'b']);
    });

    test('react adds my reaction and increments the count', () async {
      final svc = FakeFeedService(initial: [_item('a')]);
      await svc.react('a', '🔥');
      final item = (await svc.crewFeed()).single;
      final r = item.reactionFor('🔥');
      expect(r.count, 1);
      expect(r.reactedByMe, isTrue);
    });

    test('react is idempotent (no double count)', () async {
      final svc = FakeFeedService(initial: [_item('a')]);
      await svc.react('a', '🔥');
      await svc.react('a', '🔥');
      expect((await svc.crewFeed()).single.reactionFor('🔥').count, 1);
    });

    test('unreact removes my reaction and clears the tally at zero', () async {
      final svc = FakeFeedService(initial: [
        _item('a', reactions: const [
          FeedReaction(emoji: '🔥', count: 1, reactedByMe: true),
        ]),
      ]);
      await svc.unreact('a', '🔥');
      final item = (await svc.crewFeed()).single;
      expect(item.reactionFor('🔥').count, 0);
      expect(item.reactions.where((r) => r.emoji == '🔥'), isEmpty);
    });

    test('unreact leaves other reactors\' count intact', () async {
      final svc = FakeFeedService(initial: [
        _item('a', reactions: const [
          FeedReaction(emoji: '🔥', count: 2, reactedByMe: true),
        ]),
      ]);
      await svc.unreact('a', '🔥');
      expect((await svc.crewFeed()).single.reactionFor('🔥').count, 1);
    });

    test('react on an unknown item is a no-op', () async {
      final svc = FakeFeedService(initial: [_item('a')]);
      await svc.react('missing', '🔥');
      expect((await svc.crewFeed()).single.reactionFor('🔥').count, 0);
    });

    test('publishWake records the posted wake', () async {
      final svc = FakeFeedService();
      final at = DateTime.utc(2026, 7, 21, 6, 30);
      await svc.publishWake(wokeAt: at, onTime: true, streak: 5);
      expect(svc.published, hasLength(1));
      expect(svc.published.single.onTime, isTrue);
      expect(svc.published.single.streak, 5);
    });
  });

  group('DisabledFeedService', () {
    test('feed is empty and writes never throw', () async {
      const svc = DisabledFeedService();
      expect(await svc.crewFeed(), isEmpty);
      await svc.publishWake(
          wokeAt: DateTime.utc(2026), onTime: true, streak: 1);
      await svc.react('a', '🔥');
      await svc.unreact('a', '🔥');
    });
  });
}
