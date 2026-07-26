import 'crew_member.dart';
import 'crew_standing.dart';

/// One row of a group's single member list: the roster profile joined (by id)
/// with its leaderboard standing, if any. [rank] is 1-based for ranked rows
/// and null for members with no wake data yet.
class RosterEntry {
  const RosterEntry({required this.member, this.standing, this.rank});

  final CrewMember member;
  final CrewStanding? standing;
  final int? rank;
}

/// Merges a group's leaderboard [standings] and its [members] roster into the
/// ONE list the group page renders — every person appears exactly once.
///
/// Ranked rows come first, in standings order (rank 1..n). Members without a
/// standing follow alphabetically by username, unranked. A standing whose user
/// is missing from the roster (e.g. the roster fetch raced a join) still
/// renders, synthesized from the standing's own profile fields. Rows join by
/// id — usernames can change; ids cannot.
List<RosterEntry> mergeRoster(
    List<CrewStanding> standings, List<CrewMember> members) {
  final byId = {for (final m in members) m.id: m};
  final ranked = <RosterEntry>[
    for (var i = 0; i < standings.length; i++)
      RosterEntry(
        member: byId[standings[i].id] ??
            CrewMember(
              id: standings[i].id,
              username: standings[i].username,
              displayName: standings[i].displayName,
              avatarColor: standings[i].avatarColor,
            ),
        standing: standings[i],
        rank: i + 1,
      ),
  ];
  final rankedIds = {for (final s in standings) s.id};
  final rest = members.where((m) => !rankedIds.contains(m.id)).toList()
    ..sort((a, b) => a.username.compareTo(b.username));
  return [...ranked, for (final m in rest) RosterEntry(member: m)];
}
