import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/supabase_config.dart';
import '../../data/feed/feed_service.dart';
import '../../data/feed/supabase_feed_service.dart';
import '../../domain/feed_item.dart';
import 'auth_providers.dart';

/// The app's [FeedService]. Configured → a real [SupabaseFeedService]; otherwise
/// a [DisabledFeedService] (empty feed, writes are no-ops). Tests override this
/// with a `FakeFeedService`.
final feedServiceProvider = Provider<FeedService>((ref) {
  if (!SupabaseConfig.isConfigured) {
    return const DisabledFeedService();
  }
  return SupabaseFeedService();
});

/// The crew activity feed (own + accepted-crew wakes, newest first, with
/// reactions). Cached for the whole session (warmed by SocialWarmupHost, kept
/// across tab switches so reopening Crew never spins); refresh with
/// `ref.invalidate(crewFeedProvider)` after posting, on pull-to-refresh, or on
/// tab open — a reaction change instead goes through
/// [CrewFeedNotifier.setReaction], which updates instantly rather than
/// waiting on a second network round trip. Keyed to the signed-in account id
/// so a sign-out/sign-in swap can never serve another account's cached feed.
/// Empty while loading, unconfigured, or signed out — the app is fully usable
/// regardless.
final crewFeedProvider =
    AsyncNotifierProvider<CrewFeedNotifier, List<FeedItem>>(
        CrewFeedNotifier.new);

class CrewFeedNotifier extends AsyncNotifier<List<FeedItem>> {
  @override
  Future<List<FeedItem>> build() {
    ref.watch(accountProvider.select((a) => a.value?.id));
    return ref.watch(feedServiceProvider).crewFeed();
  }

  /// Reflects a reaction change on [feedId] immediately — the tally the user
  /// just tapped is visible before the network write even starts, matching
  /// the instant feel of a chat-app reaction rather than waiting on a write
  /// plus a full feed refetch. Reverts to the prior state if the write
  /// actually fails (rethrown so the caller can tell the user); a failure the
  /// service itself swallows (there is none left — see SupabaseFeedService)
  /// would otherwise leave a wrong optimistic tally in place forever.
  Future<void> setReaction(String feedId, String emoji, bool reacted) async {
    final current = state.valueOrNull;
    if (current == null) {
      // No local snapshot yet to patch — just perform the write and let the
      // in-flight build() supply the real state once it resolves.
      await _write(feedId, emoji, reacted);
      return;
    }
    state = AsyncData(_patched(current, feedId, emoji, reacted));
    try {
      await _write(feedId, emoji, reacted);
    } catch (e) {
      state = AsyncData(current); // the write didn't happen — undo the patch
      rethrow;
    }
  }

  Future<void> _write(String feedId, String emoji, bool reacted) {
    final service = ref.read(feedServiceProvider);
    return reacted
        ? service.react(feedId, emoji)
        : service.unreact(feedId, emoji);
  }

  List<FeedItem> _patched(
      List<FeedItem> items, String feedId, String emoji, bool reacted) {
    return [
      for (final item in items)
        if (item.id == feedId) _patchedItem(item, emoji, reacted) else item,
    ];
  }

  FeedItem _patchedItem(FeedItem item, String emoji, bool reacted) {
    final existing = item.reactionFor(emoji);
    if (existing.reactedByMe == reacted) return item; // already there
    final nextCount = existing.count + (reacted ? 1 : -1);
    final others = item.reactions.where((r) => r.emoji != emoji).toList();
    final reactions = nextCount > 0
        ? [...others, FeedReaction(emoji: emoji, count: nextCount, reactedByMe: reacted)]
        : others;
    return item.copyWith(reactions: reactions);
  }
}
