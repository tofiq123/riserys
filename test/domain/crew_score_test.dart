import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/crew_score.dart';
import 'package:rise/domain/crew_standing.dart';
import 'package:rise/domain/wake_stats.dart';

CrewStanding _s(String id,
        {int current = 0,
        int best = 0,
        int total = 0,
        int onTime = 0,
        bool isMe = false}) =>
    CrewStanding(
      id: id,
      username: id,
      displayName: id,
      avatarColor: '#7C9CF4',
      stats: WakeStats(
          currentStreak: current,
          bestStreak: best,
          totalWakes: total,
          onTimeCount: onTime),
      isMe: isMe,
    );

void main() {
  group('memberPoints', () {
    test('is streak*weight plus the on-time reliability bonus', () {
      // 5-day streak, 8/10 on time -> 5*3 + round(0.8*10) = 15 + 8 = 23.
      final s = _s('a', current: 5, total: 10, onTime: 8).stats;
      expect(memberPoints(s), 23);
    });

    test('a perfect rate earns the full bonus', () {
      final s = _s('a', current: 0, total: 4, onTime: 4).stats;
      expect(memberPoints(s), kRateBonus); // 0 + round(1.0*10)
    });

    test('no finalized wakes contributes no reliability bonus', () {
      final s = _s('a', current: 3, total: 0, onTime: 0).stats;
      expect(memberPoints(s), 3 * kStreakWeight);
    });

    test('best streak does not affect the score (momentum, not history)', () {
      final withBest = _s('a', current: 2, best: 99, total: 2, onTime: 2).stats;
      final without = _s('a', current: 2, best: 2, total: 2, onTime: 2).stats;
      expect(memberPoints(withBest), memberPoints(without));
    });
  });

  group('computeCrewScore', () {
    test('empty standings -> empty score', () {
      expect(computeCrewScore(const []), CrewScore.empty);
      expect(computeCrewScore(const []).crewTotal, 0);
    });

    test('crew total is the sum of member points (group aggregate)', () {
      final score = computeCrewScore([
        _s('a', current: 5, total: 10, onTime: 8), // 23
        _s('b', current: 2, total: 2, onTime: 1), // 6 + 5 = 11
      ]);
      expect(score.crewTotal, 34);
      expect(score.memberCount, 2);
    });

    test('contributions are ranked by points desc, username tiebreak', () {
      final score = computeCrewScore([
        _s('c', current: 1), // 3
        _s('a', current: 4), // 12
        _s('b', current: 4), // 12 -> ties a, username orders a before b
      ]);
      expect(score.contributions.map((c) => c.id), ['a', 'b', 'c']);
    });

    test('share percent is each member share of the crew total', () {
      final score = computeCrewScore([
        _s('a', current: 10), // 30
        _s('b', current: 10), // 30
      ]);
      expect(score.crewTotal, 60);
      expect(score.contributions.every((c) => c.sharePercent == 50), isTrue);
    });

    test('you exposes the signed-in members contribution', () {
      final score = computeCrewScore([
        _s('a', current: 6),
        _s('me', current: 2, isMe: true),
      ]);
      expect(score.you, isNotNull);
      expect(score.you!.id, 'me');
      expect(score.you!.isMe, isTrue);
    });

    test('you is null when no member is flagged isMe', () {
      final score = computeCrewScore([_s('a', current: 6)]);
      expect(score.you, isNull);
    });

    test('does not mutate the input list', () {
      final input = [_s('a', current: 1), _s('b', current: 9)];
      computeCrewScore(input);
      expect(input.map((s) => s.id), ['a', 'b']);
    });

    test('all-zero crew: total 0, shares 0, no divide-by-zero', () {
      final score = computeCrewScore([_s('a'), _s('b')]);
      expect(score.crewTotal, 0);
      expect(score.contributions.every((c) => c.sharePercent == 0), isTrue);
    });
  });
}
