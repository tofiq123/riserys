import 'crew_standing.dart';

/// A running (or ended) group "streak race" — just a marker for WHEN the race
/// began. Standings are derived from members' current streaks + [startedAt], so
/// there is no per-member state to store (see [challengeStandings]).
class GroupChallenge {
  const GroupChallenge({
    required this.id,
    required this.groupId,
    required this.startedAt,
    this.endedAt,
  });

  final String id;
  final String groupId;
  final DateTime startedAt;

  /// null while the race is still running.
  final DateTime? endedAt;

  bool get isActive => endedAt == null;

  @override
  bool operator ==(Object other) =>
      other is GroupChallenge &&
      other.id == id &&
      other.groupId == groupId &&
      other.startedAt == startedAt &&
      other.endedAt == endedAt;

  @override
  int get hashCode => Object.hash(id, groupId, startedAt, endedAt);
}

/// One row of a streak-race standings list: a leaderboard [standing] plus
/// whether that member is still [inRace].
class ChallengeStanding {
  const ChallengeStanding({required this.standing, required this.inRace});
  final CrewStanding standing;
  final bool inRace;
}

/// Whole calendar days a race has run — a UTC day count, clamped at 0 so a
/// clock skew or a just-started race never goes negative.
int challengeDayCount({required DateTime startedAt, required DateTime now}) {
  final days = now.toUtc().difference(startedAt.toUtc()).inDays;
  return days < 0 ? 0 : days;
}

/// Derives the streak-race standings from the group leaderboard [standings] and
/// the race start. A member is "in" while their current streak still covers the
/// whole race (streak >= days elapsed); a broken streak drops below that and
/// they're "out". Day 0 → everyone in. Sorted in-first, each group then in the
/// usual leaderboard order (streak desc, …). Pure + deterministic.
List<ChallengeStanding> challengeStandings({
  required DateTime startedAt,
  required DateTime now,
  required List<CrewStanding> standings,
}) {
  final days = challengeDayCount(startedAt: startedAt, now: now);
  final ranked = rankStandings(standings);
  final inRace = <CrewStanding>[];
  final out = <CrewStanding>[];
  for (final s in ranked) {
    (s.stats.currentStreak >= days ? inRace : out).add(s);
  }
  return [
    for (final s in inRace) ChallengeStanding(standing: s, inRace: true),
    for (final s in out) ChallengeStanding(standing: s, inRace: false),
  ];
}
