import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/supabase_config.dart';
import '../../data/feed/feed_service.dart';
import '../../data/feed/supabase_feed_service.dart';
import '../../domain/feed_item.dart';

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
/// reactions). Fetch-on-open; refresh with `ref.invalidate(crewFeedProvider)`
/// after posting or reacting. Empty while loading, unconfigured, or signed out —
/// the app is fully usable regardless.
final crewFeedProvider = FutureProvider.autoDispose<List<FeedItem>>((ref) {
  return ref.watch(feedServiceProvider).crewFeed();
});
