import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/leaderboard/leaderboard_service.dart';
import 'package:rise/domain/crew_standing.dart';
import 'package:rise/domain/wake_stats.dart';
import 'package:rise/ui/state/leaderboard_providers.dart';

CrewStanding _s(String id, int current) => CrewStanding(
    id: id,
    username: id,
    displayName: id,
    avatarColor: '#7C9CF4',
    stats: WakeStats(currentStreak: current));

void main() {
  test('unconfigured: leaderboardServiceProvider is Disabled, leaderboard empty',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(leaderboardServiceProvider),
        isA<DisabledLeaderboardService>());
    expect(await container.read(leaderboardProvider.future), isEmpty);
  });

  test('leaderboardProvider returns the (overridden) fake ranked list', () async {
    final fake = FakeLeaderboardService(
        standings: [_s('a', 2), _s('b', 5), _s('c', 3)]);
    final container = ProviderContainer(overrides: [
      leaderboardServiceProvider.overrideWithValue(fake),
    ]);
    addTearDown(container.dispose);
    final ranked = await container.read(leaderboardProvider.future);
    expect(ranked.map((s) => s.id), ['b', 'c', 'a']);
  });
}
