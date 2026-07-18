import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/supabase_config.dart';
import '../../data/leaderboard/leaderboard_service.dart';
import '../../data/leaderboard/supabase_leaderboard_service.dart';
import '../../domain/crew_standing.dart';

/// The app's [LeaderboardService]. Configured → a real [SupabaseLeaderboardService];
/// otherwise a [DisabledLeaderboardService] (empty, publish is a no-op). Tests
/// override this with a `FakeLeaderboardService`.
final leaderboardServiceProvider = Provider<LeaderboardService>((ref) {
  if (!SupabaseConfig.isConfigured) {
    return const DisabledLeaderboardService();
  }
  return SupabaseLeaderboardService();
});

/// The crew leaderboard (own + accepted-crew, ranked). Fetch-on-open; refresh
/// with `ref.invalidate(leaderboardProvider)`. Empty while loading, unconfigured,
/// or signed out — the app is usable regardless.
final leaderboardProvider = FutureProvider<List<CrewStanding>>((ref) {
  return ref.watch(leaderboardServiceProvider).fetchLeaderboard();
});
