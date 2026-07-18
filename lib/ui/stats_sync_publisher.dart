import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/wake_event.dart';
import '../domain/wake_stats.dart';
import '../data/leaderboard/leaderboard_service.dart';
import 'state/auth_providers.dart';
import 'state/leaderboard_providers.dart';
import 'state/wake_providers.dart';

/// Deduplicates stats publishes: only forwards a value that differs from the
/// last one published, so watching the derived stats doesn't spam the backend
/// on every rebuild.
class StatsSyncPublisher {
  StatsSyncPublisher(this._service);

  final LeaderboardService _service;
  WakeStats? _last;

  Future<void> maybePublish(WakeStats stats) async {
    if (stats == _last) return;
    _last = stats;
    await _service.publishStats(stats);
  }
}

final statsSyncPublisherProvider = Provider<StatsSyncPublisher>(
    (ref) => StatsSyncPublisher(ref.watch(leaderboardServiceProvider)));

/// The signed-in user's own [WakeStats], derived from local wake data, or
/// [WakeStats.empty] when signed out. Recomputes when wake events / streak
/// change (the live DB stream drives this, including after a background
/// dismissal is processed).
final derivedStatsProvider = Provider<WakeStats>((ref) {
  final account = ref.watch(accountProvider).value;
  if (account == null) return WakeStats.empty;
  final events = ref.watch(wakeEventsProvider).value ?? const <WakeEvent>[];
  final streak = ref.watch(streakProvider);
  return computeWakeStats(events, streak);
});

/// Mounted in the app shell: publishes the signed-in user's derived stats
/// whenever they change. Renders [child].
class StatsSyncHost extends ConsumerStatefulWidget {
  const StatsSyncHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<StatsSyncHost> createState() => _StatsSyncHostState();
}

class _StatsSyncHostState extends ConsumerState<StatsSyncHost> {
  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(accountProvider).value != null;
    if (signedIn) {
      final stats = ref.watch(derivedStatsProvider);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(ref.read(statsSyncPublisherProvider).maybePublish(stats));
      });
    }
    return widget.child;
  }
}
