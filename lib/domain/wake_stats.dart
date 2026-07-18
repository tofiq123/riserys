import 'streak.dart';
import 'wake_event.dart';

/// Aggregate wake stats for one user, published for the crew leaderboard.
class WakeStats {
  const WakeStats({
    this.currentStreak = 0,
    this.bestStreak = 0,
    this.totalWakes = 0,
    this.onTimeCount = 0,
  });

  final int currentStreak;
  final int bestStreak;
  final int totalWakes;
  final int onTimeCount;

  double get onTimeRate => totalWakes == 0 ? 0 : onTimeCount / totalWakes;

  static const empty = WakeStats();

  @override
  bool operator ==(Object other) =>
      other is WakeStats &&
      other.currentStreak == currentStreak &&
      other.bestStreak == bestStreak &&
      other.totalWakes == totalWakes &&
      other.onTimeCount == onTimeCount;

  @override
  int get hashCode =>
      Object.hash(currentStreak, bestStreak, totalWakes, onTimeCount);
}

/// Derives [WakeStats] from the local wake log + computed streak. Only finalized
/// (dismissed) events count toward totals; the streak values pass through.
WakeStats computeWakeStats(List<WakeEvent> events, StreakStats streak) {
  var total = 0;
  var onTime = 0;
  for (final e in events) {
    if (e.dismissedAt != null) {
      total++;
      if (e.onTime) onTime++;
    }
  }
  return WakeStats(
    currentStreak: streak.current,
    bestStreak: streak.best,
    totalWakes: total,
    onTimeCount: onTime,
  );
}
