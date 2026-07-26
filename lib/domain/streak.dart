import 'wake_event.dart';

/// How a single local calendar day is judged for the streak.
enum DayOutcome { success, miss, neutral, pending }

class StreakStats {
  const StreakStats({
    required this.current,
    required this.best,
    required this.freezesRemaining,
    required this.byDay,
    this.freezeAbsorbed = const <DateTime>{},
    this.runByDay = const <DateTime, int>{},
  });

  final int current;
  final int best;
  final int freezesRemaining;

  /// Keyed by local-midnight day. Days absent from the map are neutral.
  final Map<DateTime, DayOutcome> byDay;

  /// The local-midnight days that WOULD have broken the run but were covered by
  /// a banked freeze. The day stays a [DayOutcome.miss] in [byDay] — this set
  /// only records that the run survived it, so the UI can say why without
  /// rewriting the outcome. Empty unless [computeStreak] produced it.
  final Set<DateTime> freezeAbsorbed;

  /// The run length as it stood at the end of each folded day. Recorded by the
  /// same pass that computes [current], so a chart of the streak over time can
  /// never disagree with the number above it. Empty unless [computeStreak]
  /// produced it.
  final Map<DateTime, int> runByDay;

  /// The run at the end of each of the last [days] local days, oldest first.
  /// Days the fold skipped (no alarm, a rest day) carry the run forward, which
  /// is what actually happened to it.
  List<int> runSeries(DateTime now, {int days = 30}) {
    final l = now.toLocal();
    final today = DateTime(l.year, l.month, l.day);
    final out = <int>[];
    var carried = 0;
    // Seed from before the window so the series starts at the true run, not 0.
    for (final entry in (runByDay.keys.toList()..sort())) {
      if (entry.isBefore(today.subtract(Duration(days: days - 1)))) {
        carried = runByDay[entry]!;
      }
    }
    for (var i = days - 1; i >= 0; i--) {
      final day = today.subtract(Duration(days: i));
      carried = runByDay[day] ?? carried;
      out.add(carried);
    }
    return out;
  }

  static const empty = StreakStats(
      current: 0, best: 0, freezesRemaining: 0, byDay: <DateTime, DayOutcome>{});
}

/// Folds the wake-event log into streak stats. Pure and deterministic: the
/// streak is always recomputed from events, never stored, so it cannot desync.
///
/// - A day SUCCEEDS if it has any on-time event.
/// - A past day with rings but no on-time dismissal is a MISS.
/// - Today with rings but not yet an on-time success is PENDING (streak holds).
/// - A day with no events is NEUTRAL (absent from [StreakStats.byDay]; skipped).
/// - A freeze (earned 1 per [earnEvery] consecutive successes, capped at
///   [freezeCap]) is consumed by a miss before the streak breaks.
///
/// [excusedDays] are local-midnight days the user marked as a "rough night".
/// A past day in this set that would otherwise be a MISS becomes NEUTRAL — the
/// streak neither breaks nor advances over it. This is abuse-safe by design:
/// an excused day never *advances* a streak, only prevents a break, so no
/// gamification cap is needed. Excusing a success or a no-event day is a no-op.
StreakStats computeStreak(
  List<WakeEvent> events,
  DateTime now, {
  int freezeCap = 2,
  int earnEvery = 7,
  Set<DateTime> excusedDays = const {},
}) {
  final ln = now.toLocal();
  final today = DateTime(ln.year, ln.month, ln.day);

  // A day is on-time if ANY of its events is on-time.
  final hasOnTime = <DateTime, bool>{};
  for (final e in events) {
    final day = e.localDay;
    hasOnTime[day] = (hasOnTime[day] ?? false) || e.onTime;
  }

  final byDay = <DateTime, DayOutcome>{};
  hasOnTime.forEach((day, onTime) {
    if (day.isAfter(today)) return; // ignore future days (shouldn't occur)
    if (onTime) {
      byDay[day] = DayOutcome.success;
    } else if (day.isAtSameMomentAs(today)) {
      byDay[day] = DayOutcome.pending;
    } else {
      // A past miss the user excused (a "rough night") holds the streak: it
      // becomes neutral, so the fold neither breaks nor advances over it.
      byDay[day] =
          excusedDays.contains(day) ? DayOutcome.neutral : DayOutcome.miss;
    }
  });

  // Fold every past day, plus today only once it is already a success.
  final foldDays = byDay.keys
      .where((day) => day.isBefore(today) || byDay[day] == DayOutcome.success)
      .toList()
    ..sort();

  var run = 0;
  var best = 0;
  var freezes = 0;
  final absorbed = <DateTime>{};
  final runByDay = <DateTime, int>{};
  for (final day in foldDays) {
    switch (byDay[day]) {
      case DayOutcome.success:
        run++;
        if (run % earnEvery == 0 && freezes < freezeCap) freezes++;
        if (run > best) best = run;
      case DayOutcome.miss:
        if (freezes > 0) {
          freezes--; // absorbed — the run holds
          absorbed.add(day);
        } else {
          run = 0;
          // A break resets the ledger: earlier absorptions belong to a run that
          // no longer exists, so they must not be reported against this one.
          absorbed.clear();
        }
      case DayOutcome.neutral:
      case DayOutcome.pending:
      case null:
        break;
    }
    // Recorded by the same pass, so a chart of the run can never drift from
    // the number the fold ends on.
    runByDay[day] = run;
  }

  return StreakStats(
      current: run,
      best: best,
      freezesRemaining: freezes,
      byDay: byDay,
      freezeAbsorbed: absorbed,
      runByDay: runByDay);
}
