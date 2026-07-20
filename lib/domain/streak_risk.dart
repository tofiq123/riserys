import 'streak.dart';

/// Whether the user's streak needs a nudge of encouragement right now.
///
/// - [atRisk]: a live streak is on the line today (an alarm rang but there's
///   not yet an on-time success).
/// - [broke]: the streak just reset — yesterday was a miss and the run is now 0.
/// - [none]: nothing to prompt about.
enum StreakRisk { none, atRisk, broke }

/// Derives a [StreakRisk] purely from already-computed [StreakStats], with no
/// new backend or time-of-day heuristics beyond [now]. Deterministic.
///
/// A fresh break ([broke]) is detected only when *yesterday* was the miss, so
/// the prompt stays timely ("you just broke — get back on it"), never nagging
/// about an old lapse. [atRisk] fires only when there is a streak worth
/// protecting (current > 0). [broke] takes precedence over [atRisk].
StreakRisk streakRisk(StreakStats stats, DateTime now) {
  final ln = now.toLocal();
  final today = DateTime(ln.year, ln.month, ln.day);
  final yesterday = today.subtract(const Duration(days: 1));

  if (stats.current == 0 && stats.byDay[yesterday] == DayOutcome.miss) {
    return StreakRisk.broke;
  }
  if (stats.current > 0 && stats.byDay[today] == DayOutcome.pending) {
    return StreakRisk.atRisk;
  }
  return StreakRisk.none;
}
