import '../../domain/crew_standing.dart';
import '../../domain/wake_stats.dart';

/// Publishes the signed-in user's aggregate wake stats and fetches the crew
/// leaderboard (own + accepted-crew, ranked). Production is
/// `SupabaseLeaderboardService`; tests use [FakeLeaderboardService];
/// unconfigured/signed-out uses [DisabledLeaderboardService].
abstract interface class LeaderboardService {
  /// Upserts the signed-in user's own stats. Best-effort — never throws into
  /// the alarm path.
  Future<void> publishStats(WakeStats stats);

  /// Own + accepted-crew standings, ranked by [rankStandings].
  Future<List<CrewStanding>> fetchLeaderboard();
}

/// In-memory [LeaderboardService] for tests: records the last published stats
/// and returns a seeded (then ranked) list.
class FakeLeaderboardService implements LeaderboardService {
  FakeLeaderboardService({List<CrewStanding> standings = const []})
      : _standings = standings;

  final List<CrewStanding> _standings;

  WakeStats? lastPublished;
  int publishCount = 0;

  @override
  Future<void> publishStats(WakeStats stats) async {
    lastPublished = stats;
    publishCount++;
  }

  @override
  Future<List<CrewStanding>> fetchLeaderboard() async =>
      rankStandings(_standings);
}

/// Used when unconfigured/signed-out: publish is a no-op, the leaderboard is
/// empty. Never throws.
class DisabledLeaderboardService implements LeaderboardService {
  const DisabledLeaderboardService();

  @override
  Future<void> publishStats(WakeStats stats) async {}

  @override
  Future<List<CrewStanding>> fetchLeaderboard() async => const [];
}
