import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/supabase_config.dart';
import '../../data/leaderboard/leaderboard_service.dart';
import '../../data/leaderboard/supabase_leaderboard_service.dart';
import '../../domain/crew_standing.dart';
import 'auth_providers.dart';

/// The app's [LeaderboardService]. Configured → a real [SupabaseLeaderboardService];
/// otherwise a [DisabledLeaderboardService] (empty, publish is a no-op). Tests
/// override this with a `FakeLeaderboardService`.
final leaderboardServiceProvider = Provider<LeaderboardService>((ref) {
  if (!SupabaseConfig.isConfigured) {
    return const DisabledLeaderboardService();
  }
  return SupabaseLeaderboardService();
});

/// The crew leaderboard (own + accepted-crew, ranked). Cached for the session
/// (warmed at shell level); refresh with `ref.invalidate(leaderboardProvider)`.
/// Keyed to the signed-in account id so standings never leak across accounts.
/// Empty while loading, unconfigured, or signed out — the app is usable
/// regardless.
final leaderboardProvider = FutureProvider<List<CrewStanding>>((ref) {
  ref.watch(accountProvider.select((a) => a.value?.id));
  return ref.watch(leaderboardServiceProvider).fetchLeaderboard();
});
