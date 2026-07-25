import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/crew_standing.dart';
import 'package:rise/domain/group_challenge.dart';
import 'package:rise/domain/wake_stats.dart';

void main() {
  CrewStanding member(String id, int streak) => CrewStanding(
        id: id,
        username: id,
        displayName: id,
        avatarColor: '#000000',
        stats: WakeStats(currentStreak: streak, bestStreak: streak),
      );

  group('GroupChallenge', () {
    test('isActive is true until ended', () {
      expect(
        GroupChallenge(id: 'c', groupId: 'g', startedAt: DateTime.utc(2026))
            .isActive,
        isTrue,
      );
      expect(
        GroupChallenge(
          id: 'c',
          groupId: 'g',
          startedAt: DateTime.utc(2026),
          endedAt: DateTime.utc(2026, 1, 5),
        ).isActive,
        isFalse,
      );
    });
  });

  group('challengeDayCount', () {
    final start = DateTime.utc(2026, 1, 1, 6);
    test('is 0 on the first day and never negative', () {
      expect(challengeDayCount(startedAt: start, now: start), 0);
      expect(
        challengeDayCount(
            startedAt: start, now: start.subtract(const Duration(hours: 5))),
        0,
      );
    });
    test('counts whole elapsed days', () {
      expect(
        challengeDayCount(
            startedAt: start, now: start.add(const Duration(days: 3, hours: 2))),
        3,
      );
    });
  });

  group('challengeStandings', () {
    final start = DateTime.utc(2026, 1, 1, 6);
    final day3 = start.add(const Duration(days: 3, hours: 1)); // 3 days elapsed

    test('day 0: everyone is in, ranked by streak', () {
      final out = challengeStandings(
        startedAt: start,
        now: start,
        standings: [member('a', 2), member('b', 10), member('c', 0)],
      );
      expect(out.map((s) => s.standing.id).toList(), ['b', 'a', 'c']);
      expect(out.every((s) => s.inRace), isTrue);
    });

    test('members whose streak covers the race stay in; the rest drop out', () {
      final out = challengeStandings(
        startedAt: start,
        now: day3, // 3 days in
        standings: [
          member('kept', 5), // >= 3 -> in
          member('exactly', 3), // == 3 -> in (boundary)
          member('broke', 1), // < 3 -> out
          member('reset', 0), // out
        ],
      );
      final byId = {for (final s in out) s.standing.id: s.inRace};
      expect(byId['kept'], isTrue);
      expect(byId['exactly'], isTrue);
      expect(byId['broke'], isFalse);
      expect(byId['reset'], isFalse);
    });

    test('in-race members sort before out members regardless of raw streak', () {
      final out = challengeStandings(
        startedAt: start,
        now: day3,
        standings: [
          member('out_high', 1), // out, though a higher streak than in_low
          member('in_low', 3), // in
        ],
      );
      expect(out.first.standing.id, 'in_low');
      expect(out.first.inRace, isTrue);
      expect(out.last.standing.id, 'out_high');
      expect(out.last.inRace, isFalse);
    });

    test('empty standings yields empty', () {
      expect(
        challengeStandings(startedAt: start, now: day3, standings: const []),
        isEmpty,
      );
    });
  });
}
