import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/leaderboard/leaderboard_service.dart';
import 'package:rise/domain/crew_standing.dart';
import 'package:rise/domain/wake_stats.dart';

CrewStanding _s(String id, int current) => CrewStanding(
    id: id,
    username: id,
    displayName: id,
    avatarColor: '#7C9CF4',
    stats: WakeStats(currentStreak: current));

void main() {
  group('FakeLeaderboardService', () {
    test('publishStats records the value and counts calls', () async {
      final svc = FakeLeaderboardService();
      expect(svc.lastPublished, isNull);
      await svc.publishStats(const WakeStats(currentStreak: 3));
      await svc.publishStats(const WakeStats(currentStreak: 4));
      expect(svc.lastPublished, const WakeStats(currentStreak: 4));
      expect(svc.publishCount, 2);
    });

    test('fetchLeaderboard returns the seeded standings, ranked', () async {
      final svc = FakeLeaderboardService(
          standings: [_s('a', 2), _s('b', 5), _s('c', 3)]);
      final ranked = await svc.fetchLeaderboard();
      expect(ranked.map((s) => s.id), ['b', 'c', 'a']);
    });
  });

  group('DisabledLeaderboardService', () {
    const svc = DisabledLeaderboardService();
    test('publish is a no-op and fetch is empty', () async {
      await svc.publishStats(const WakeStats(currentStreak: 9)); // must not throw
      expect(await svc.fetchLeaderboard(), isEmpty);
    });
  });
}
