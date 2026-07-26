import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/crew_member.dart';
import 'package:rise/domain/crew_standing.dart';
import 'package:rise/domain/group_roster.dart';
import 'package:rise/domain/wake_stats.dart';

CrewMember _m(String id, String username) => CrewMember(
    id: id, username: username, displayName: username, avatarColor: '#7C9CF4');

CrewStanding _s(String id, String username, {int streak = 3}) => CrewStanding(
      id: id,
      username: username,
      displayName: username,
      avatarColor: '#7C9CF4',
      stats: WakeStats(
          currentStreak: streak,
          bestStreak: streak,
          totalWakes: 10,
          onTimeCount: 8),
    );

void main() {
  test('standings come first, ranked 1..n in standings order', () {
    final roster = mergeRoster(
      [_s('a', 'ada'), _s('b', 'bo')],
      [_m('a', 'ada'), _m('b', 'bo')],
    );
    expect(roster, hasLength(2));
    expect(roster[0].rank, 1);
    expect(roster[0].member.id, 'a');
    expect(roster[0].standing, isNotNull);
    expect(roster[1].rank, 2);
    expect(roster[1].member.id, 'b');
  });

  test('roster members without a standing append unranked, alphabetically',
      () {
    final roster = mergeRoster(
      [_s('a', 'ada')],
      [_m('z', 'zed'), _m('a', 'ada'), _m('c', 'cid')],
    );
    expect(roster.map((e) => e.member.id), ['a', 'c', 'z']);
    expect(roster[0].rank, 1);
    expect(roster[1].rank, isNull);
    expect(roster[1].standing, isNull);
    expect(roster[2].rank, isNull);
  });

  test('a standing with no roster row still renders from its own fields', () {
    final roster = mergeRoster([_s('a', 'ada')], const []);
    expect(roster, hasLength(1));
    expect(roster[0].member.username, 'ada');
    expect(roster[0].rank, 1);
  });

  test('join is by id, not username', () {
    final roster = mergeRoster(
      [_s('a', 'renamed')],
      [_m('a', 'ada')],
    );
    expect(roster, hasLength(1));
    // The roster row (profile truth) wins for member fields.
    expect(roster[0].member.username, 'ada');
    expect(roster[0].standing!.username, 'renamed');
  });
}
