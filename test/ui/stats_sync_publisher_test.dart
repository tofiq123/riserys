import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/auth/auth_service.dart';
import 'package:rise/data/leaderboard/leaderboard_service.dart';
import 'package:rise/domain/streak.dart';
import 'package:rise/domain/wake_event.dart';
import 'package:rise/domain/wake_stats.dart';
import 'package:rise/ui/state/auth_providers.dart';
import 'package:rise/ui/state/leaderboard_providers.dart';
import 'package:rise/ui/state/wake_providers.dart';
import 'package:rise/ui/stats_sync_publisher.dart';

WakeEvent _finalized(int id, {bool onTime = true}) => WakeEvent(
      id: id,
      alarmId: 1,
      scheduledAt: DateTime.utc(2026, 7, 18, 6),
      firstRingAt: DateTime.utc(2026, 7, 18, 6),
      dismissedAt: DateTime.utc(2026, 7, 18, 6, 1),
      onTime: onTime,
    );

void main() {
  group('StatsSyncPublisher (dedup)', () {
    test('maybePublish only publishes on a changed value', () async {
      final fake = FakeLeaderboardService();
      final pub = StatsSyncPublisher(fake);
      await pub.maybePublish(const WakeStats(currentStreak: 1));
      await pub.maybePublish(const WakeStats(currentStreak: 1)); // dup
      await pub.maybePublish(const WakeStats(currentStreak: 2));
      expect(fake.publishCount, 2);
      expect(fake.lastPublished, const WakeStats(currentStreak: 2));
    });
  });

  group('StatsSyncHost', () {
    testWidgets('publishes derived stats when signed in', (t) async {
      final auth = FakeAuthService();
      await auth.signInWithGoogle();
      await auth.claimUsername('me', displayName: 'Me');
      addTearDown(auth.dispose);
      final board = FakeLeaderboardService();

      await t.pumpWidget(ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(auth),
          leaderboardServiceProvider.overrideWithValue(board),
          wakeEventsProvider.overrideWith(
              (ref) => Stream.value([_finalized(1), _finalized(2, onTime: false)])),
          streakProvider.overrideWithValue(
              const StreakStats(current: 3, best: 5, freezesRemaining: 0, byDay: {})),
        ],
        child: const MaterialApp(home: StatsSyncHost(child: SizedBox())),
      ));
      await t.pumpAndSettle();

      expect(board.lastPublished, isNotNull);
      expect(board.lastPublished!.currentStreak, 3);
      expect(board.lastPublished!.totalWakes, 2);
      expect(board.lastPublished!.onTimeCount, 1);
    });

    testWidgets('does not publish when signed out', (t) async {
      final board = FakeLeaderboardService();
      await t.pumpWidget(ProviderScope(
        overrides: [leaderboardServiceProvider.overrideWithValue(board)],
        child: const MaterialApp(home: StatsSyncHost(child: SizedBox())),
      ));
      await t.pumpAndSettle();
      expect(board.publishCount, 0);
    });
  });
}
