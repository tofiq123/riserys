import 'day_runs.dart';
import 'wake_event.dart';
import 'wake_insights.dart' show wakeMinuteOfDay;

/// The time window a Stats view aggregates over.
enum StatsPeriod { week, month, year }

/// Trailing window length in days for [period] (ending today, inclusive).
int periodDays(StatsPeriod period) => switch (period) {
      StatsPeriod.week => 7,
      StatsPeriod.month => 30,
      StatsPeriod.year => 365,
    };

/// Short human label for [period].
String periodLabel(StatsPeriod period) => switch (period) {
      StatsPeriod.week => 'Week',
      StatsPeriod.month => 'Month',
      StatsPeriod.year => 'Year',
    };

/// Aggregate wake metrics over one trailing period. All fields derive from
/// completed (dismissed) events; there is nothing stored, so it cannot desync.
class PeriodStats {
  const PeriodStats({
    required this.count,
    required this.onTimeCount,
    required this.avgWakeMinute,
    required this.bestStreak,
  });

  /// Completed wake-ups in the window.
  final int count;

  /// How many of those were on time.
  final int onTimeCount;

  /// Mean dismissal minute-of-day (0..1439), or null when [count] is 0.
  final int? avgWakeMinute;

  /// Longest run of consecutive on-time calendar days within the window.
  final int bestStreak;

  /// On-time share (0..1), or null when there were no wake-ups.
  double? get onTimeRate => count == 0 ? null : onTimeCount / count;

  static const empty = PeriodStats(
      count: 0, onTimeCount: 0, avgWakeMinute: null, bestStreak: 0);

  @override
  bool operator ==(Object other) =>
      other is PeriodStats &&
      other.count == count &&
      other.onTimeCount == onTimeCount &&
      other.avgWakeMinute == avgWakeMinute &&
      other.bestStreak == bestStreak;

  @override
  int get hashCode =>
      Object.hash(count, onTimeCount, avgWakeMinute, bestStreak);

  @override
  String toString() =>
      'PeriodStats(count: $count, onTime: $onTimeCount, avg: $avgWakeMinute, '
      'bestStreak: $bestStreak)';
}

/// Aggregates the [events] falling in the trailing window for [period] (7 / 30 /
/// 365 days ending on [now]'s local day, inclusive). Pure and deterministic;
/// only completed wake-ups count.
PeriodStats aggregatePeriod(
    List<WakeEvent> events, DateTime now, StatsPeriod period) {
  final ln = now.toLocal();
  final today = DateTime(ln.year, ln.month, ln.day);
  final start = today.subtract(Duration(days: periodDays(period) - 1));

  var count = 0;
  var onTimeCount = 0;
  var minuteSum = 0;
  final onTimeDays = <DateTime>{};
  for (final e in events) {
    if (e.dismissedAt == null) continue;
    final day = e.localDay;
    if (day.isBefore(start) || day.isAfter(today)) continue;
    count++;
    minuteSum += wakeMinuteOfDay(e)!;
    if (e.onTime) {
      onTimeCount++;
      onTimeDays.add(day);
    }
  }

  return PeriodStats(
    count: count,
    onTimeCount: onTimeCount,
    avgWakeMinute: count == 0 ? null : (minuteSum / count).round(),
    bestStreak: longestConsecutiveRun(onTimeDays),
  );
}
