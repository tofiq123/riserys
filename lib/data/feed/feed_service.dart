import '../../domain/feed_item.dart';

/// Posts the signed-in user's wakes to the crew feed and reads back the crew's
/// recent activity with reactions. Production is `SupabaseFeedService`; tests use
/// [FakeFeedService]; unconfigured/signed-out uses [DisabledFeedService].
///
/// Every method is graceful-degrade: reads return empty and writes are no-ops
/// (never throw) when unconfigured or signed out, so the feature simply goes
/// quiet rather than breaking the app.
abstract interface class FeedService {
  /// Recent feed items from you + accepted friends, newest first, each with its
  /// reaction summary. Empty when unconfigured/signed-out.
  Future<List<FeedItem>> crewFeed();

  /// Posts one feed item for the signed-in user's just-finished wake. Best-effort
  /// — never throws into the wake/alarm path. Idempotent per (user, [wokeAt]).
  Future<void> publishWake({
    required DateTime wokeAt,
    required bool onTime,
    required int streak,
  });

  /// Adds the signed-in user's [emoji] reaction to [feedId] (idempotent).
  Future<void> react(String feedId, String emoji);

  /// Removes the signed-in user's [emoji] reaction from [feedId] (idempotent).
  Future<void> unreact(String feedId, String emoji);
}

/// In-memory [FeedService] for unit/widget tests. [initial] seeds the feed;
/// [selfId] identifies "me" so [react]/[unreact] toggle the caller's own
/// reaction on the matching item. Records published wakes for assertions.
class FakeFeedService implements FeedService {
  FakeFeedService({List<FeedItem> initial = const [], this.selfId = 'me'})
      : _items = [...initial];

  final String selfId;
  final List<FeedItem> _items;

  final List<({DateTime wokeAt, bool onTime, int streak})> published = [];

  @override
  Future<List<FeedItem>> crewFeed() async => List.unmodifiable(_items);

  @override
  Future<void> publishWake({
    required DateTime wokeAt,
    required bool onTime,
    required int streak,
  }) async {
    published.add((wokeAt: wokeAt, onTime: onTime, streak: streak));
  }

  @override
  Future<void> react(String feedId, String emoji) async =>
      _toggle(feedId, emoji, on: true);

  @override
  Future<void> unreact(String feedId, String emoji) async =>
      _toggle(feedId, emoji, on: false);

  void _toggle(String feedId, String emoji, {required bool on}) {
    final idx = _items.indexWhere((i) => i.id == feedId);
    if (idx == -1) return;
    final item = _items[idx];
    final existing = item.reactionFor(emoji);
    if (on == existing.reactedByMe) return; // already in the desired state
    final delta = on ? 1 : -1;
    final nextCount = existing.count + delta;
    final reactions = [...item.reactions.where((r) => r.emoji != emoji)];
    if (nextCount > 0) {
      reactions.add(FeedReaction(
          emoji: emoji, count: nextCount, reactedByMe: on));
    }
    _items[idx] = item.copyWith(reactions: reactions);
  }
}

/// Used when unconfigured/signed-out: an empty feed, and every write is a no-op.
/// Never throws — the feed feature is purely additive.
class DisabledFeedService implements FeedService {
  const DisabledFeedService();

  @override
  Future<List<FeedItem>> crewFeed() async => const [];

  @override
  Future<void> publishWake({
    required DateTime wokeAt,
    required bool onTime,
    required int streak,
  }) async {}

  @override
  Future<void> react(String feedId, String emoji) async {}

  @override
  Future<void> unreact(String feedId, String emoji) async {}
}
