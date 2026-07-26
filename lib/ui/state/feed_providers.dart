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
/// `ref.invalidate(crewFeedProvider)` after posting or reacting, on pull-to-
/// refresh, or on tab open. Keyed to the signed-in account id so a sign-out/
/// sign-in swap can never serve another account's cached feed. Empty while
/// loading, unconfigured, or signed out — the app is fully usable regardless.
final crewFeedProvider = FutureProvider<List<FeedItem>>((ref) {
  ref.watch(accountProvider.select((a) => a.value?.id));
  return ref.watch(feedServiceProvider).crewFeed();
});
