import 'package:collection/collection.dart';

import 'crew_standing.dart';
import 'wake_stats.dart';

/// Weight applied to each day of a member's *current* streak. The live run is
/// the primary "are we winning together right now" signal, so it dominates.
const int kStreakWeight = 3;

/// Maximum points a member earns purely from wake-up reliability (a perfect
/// on-time rate). This gives a floor of contribution to a steady member whose
/// streak is short or just reset, so consistency — not only raw streak — counts.
const int kRateBonus = 10;

/// Points one member contributes to the crew, from their published wake stats.
///
/// `currentStreak * kStreakWeight` (live momentum) plus a reliability bonus of
/// up to [kRateBonus] scaled by on-time rate. Best streak is deliberately
/// excluded: the crew score is about present-day momentum, not history (the
/// leaderboard already surfaces best streak). Members with no finalized wakes
/// contribute no reliability bonus (rate is undefined, treated as 0).
int memberPoints(WakeStats stats) {
  final streakPoints = stats.currentStreak * kStreakWeight;
  final ratePoints =
      stats.totalWakes == 0 ? 0 : (stats.onTimeRate * kRateBonus).round();
  return streakPoints + ratePoints;
}

/// One member's slice of the crew score: their raw [points] and their [share]
/// of the crew total, as a whole percent (0–100).
class MemberContribution {
  const MemberContribution({
    required this.id,
    required this.username,
    required this.points,
    required this.sharePercent,
    required this.isMe,
  });

  final String id;
  final String username;
  final int points;
  final int sharePercent;
  final bool isMe;

  @override
  bool operator ==(Object other) =>
      other is MemberContribution &&
      other.id == id &&
      other.username == username &&
      other.points == points &&
      other.sharePercent == sharePercent &&
      other.isMe == isMe;

  @override
  int get hashCode => Object.hash(id, username, points, sharePercent, isMe);
}

/// The research's individual+group hybrid: a single crew total the whole crew
/// grows together ([crewTotal]), alongside each member's individual
/// [contributions] (ranked, with a share of the total). So the crew wins as a
/// group AND individuals are still ranked — neither pure-team nor pure-solo.
class CrewScore {
  const CrewScore({
    required this.crewTotal,
    required this.memberCount,
    required this.contributions,
  });

  /// Sum of every member's [memberPoints] — the shared, collective figure.
  final int crewTotal;
  final int memberCount;

  /// Per-member contributions, ranked by points desc (username tiebreak).
  final List<MemberContribution> contributions;

  /// The signed-in user's own contribution, if they are in the standings.
  MemberContribution? get you =>
      contributions.firstWhereOrNull((c) => c.isMe);

  static const empty =
      CrewScore(crewTotal: 0, memberCount: 0, contributions: []);
}

/// Folds ranked crew [standings] (own + accepted crew) into a [CrewScore].
/// Pure and deterministic; does not mutate [standings].
CrewScore computeCrewScore(List<CrewStanding> standings) {
  if (standings.isEmpty) return CrewScore.empty;

  final points = {for (final s in standings) s.id: memberPoints(s.stats)};
  final total = points.values.fold<int>(0, (a, b) => a + b);

  final contributions = [
    for (final s in standings)
      MemberContribution(
        id: s.id,
        username: s.username,
        points: points[s.id]!,
        sharePercent: total == 0 ? 0 : ((points[s.id]! / total) * 100).round(),
        isMe: s.isMe,
      ),
  ]..sort((a, b) {
      final byPoints = b.points.compareTo(a.points);
      if (byPoints != 0) return byPoints;
      return a.username.compareTo(b.username);
    });

  return CrewScore(
    crewTotal: total,
    memberCount: standings.length,
    contributions: contributions,
  );
}
