import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/feed_item.dart';

FeedItem _item({List<FeedReaction> reactions = const []}) => FeedItem(
      id: 'f1',
      userId: 'u1',
      username: 'ada',
      displayName: 'Ada',
      avatarColor: '#7C9CF4',
      wokeAt: DateTime.utc(2026, 7, 20, 7, 2),
      onTime: true,
      streak: 6,
      reactions: reactions,
    );

void main() {
  group('summarizeReactions', () {
    test('counts each emoji and flags the caller\'s own reaction', () {
      final summary = summarizeReactions(
        const [
          (emoji: '🔥', reactorId: 'u1'),
          (emoji: '🔥', reactorId: 'me'),
          (emoji: '👏', reactorId: 'u2'),
        ],
        myId: 'me',
      );
      final fire = summary.firstWhere((r) => r.emoji == '🔥');
      final clap = summary.firstWhere((r) => r.emoji == '👏');
      expect(fire.count, 2);
      expect(fire.reactedByMe, isTrue);
      expect(clap.count, 1);
      expect(clap.reactedByMe, isFalse);
    });

    test('orders palette emojis first in palette order, others after', () {
      final summary = summarizeReactions(
        const [
          (emoji: '🎉', reactorId: 'u1'), // non-palette
          (emoji: '💪', reactorId: 'u2'), // palette index 2
          (emoji: '🔥', reactorId: 'u3'), // palette index 0
        ],
        myId: null,
      );
      expect(summary.map((r) => r.emoji).toList(), ['🔥', '💪', '🎉']);
    });

    test('breaks ties among non-palette emojis by count desc then emoji', () {
      final summary = summarizeReactions(
        const [
          (emoji: 'b', reactorId: 'u1'),
          (emoji: 'a', reactorId: 'u2'),
          (emoji: 'a', reactorId: 'u3'), // 'a' has higher count
        ],
        myId: null,
      );
      expect(summary.map((r) => r.emoji).toList(), ['a', 'b']);
    });

    test('null myId means nothing is marked as mine', () {
      final summary = summarizeReactions(
        const [(emoji: '🔥', reactorId: 'u1')],
        myId: null,
      );
      expect(summary.single.reactedByMe, isFalse);
    });

    test('empty input yields an empty summary', () {
      expect(summarizeReactions(const [], myId: 'me'), isEmpty);
    });
  });

  group('FeedItem.reactionFor', () {
    test('returns the matching tally', () {
      final item = _item(reactions: const [
        FeedReaction(emoji: '🔥', count: 3, reactedByMe: true),
      ]);
      final r = item.reactionFor('🔥');
      expect(r.count, 3);
      expect(r.reactedByMe, isTrue);
    });

    test('returns a zero, not-reacted default for an absent emoji', () {
      final r = _item().reactionFor('👏');
      expect(r.count, 0);
      expect(r.reactedByMe, isFalse);
      expect(r.emoji, '👏');
    });
  });

  group('value semantics', () {
    test('FeedReaction equality + hashCode', () {
      const a = FeedReaction(emoji: '🔥', count: 2, reactedByMe: true);
      const b = FeedReaction(emoji: '🔥', count: 2, reactedByMe: true);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(a.copyWith(count: 3)));
    });

    test('FeedItem equality is reaction-sensitive', () {
      final base = _item();
      final withReaction = _item(reactions: const [
        FeedReaction(emoji: '🔥', count: 1, reactedByMe: false),
      ]);
      expect(_item(), base);
      expect(base, isNot(withReaction));
    });

    test('FeedItem.copyWith replaces only the given fields', () {
      final updated = _item().copyWith(streak: 10, isMe: true);
      expect(updated.streak, 10);
      expect(updated.isMe, isTrue);
      expect(updated.username, 'ada');
    });
  });

  test('kFeedReactionEmojis is the warm 4-emoji palette', () {
    expect(kFeedReactionEmojis, ['🔥', '👏', '💪', '☀️']);
  });
}
