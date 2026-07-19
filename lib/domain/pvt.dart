/// Trial parameters for a Psychomotor Vigilance Task (PVT-B) session,
/// scaled by mission difficulty.
class PvtConfig {
  const PvtConfig({
    required this.trials,
    required this.isiMinMs,
    required this.isiMaxMs,
    required this.lapseThresholdMs,
  });

  final int trials;
  final int isiMinMs;
  final int isiMaxMs;
  final int lapseThresholdMs;
}

/// Trial count scales with difficulty; timing follows the abbreviated
/// PVT-B protocol (1.5-4s inter-stimulus interval, 355ms lapse threshold).
PvtConfig pvtConfigFor(String diff) {
  final trials = switch (diff) {
    'hard' => 7,
    'medium' => 5,
    _ => 3, // easy
  };
  return PvtConfig(
      trials: trials, isiMinMs: 1500, isiMaxMs: 4000, lapseThresholdMs: 355);
}

/// Metrics computed from a completed PVT session's reaction times.
class PvtResult {
  const PvtResult({
    required this.validTaps,
    required this.lapses,
    required this.falseStarts,
    required this.meanRtMs,
    required this.medianRtMs,
    required this.minRtMs,
    required this.maxRtMs,
  });

  final int validTaps;
  final int lapses;
  final int falseStarts;
  final int meanRtMs;
  final int medianRtMs;
  final int minRtMs;
  final int maxRtMs;
}

/// Folds raw reaction times into [PvtResult]. [lapses] counts RTs strictly
/// greater than [lapseThresholdMs]. [falseStarts] is passed through
/// unchanged — it is tallied by the caller during trial collection.
PvtResult computePvtResult(
  List<int> reactionTimesMs, {
  required int falseStarts,
  int lapseThresholdMs = 355,
}) {
  if (reactionTimesMs.isEmpty) {
    return PvtResult(
      validTaps: 0,
      lapses: 0,
      falseStarts: falseStarts,
      meanRtMs: 0,
      medianRtMs: 0,
      minRtMs: 0,
      maxRtMs: 0,
    );
  }

  final sorted = [...reactionTimesMs]..sort();
  final sum = sorted.fold<int>(0, (acc, rt) => acc + rt);
  final mean = (sum / sorted.length).round();
  final mid = sorted.length ~/ 2;
  final median = sorted.length.isOdd
      ? sorted[mid]
      : ((sorted[mid - 1] + sorted[mid]) / 2).round();
  final lapses = sorted.where((rt) => rt > lapseThresholdMs).length;

  return PvtResult(
    validTaps: sorted.length,
    lapses: lapses,
    falseStarts: falseStarts,
    meanRtMs: mean,
    medianRtMs: median,
    minRtMs: sorted.first,
    maxRtMs: sorted.last,
  );
}

/// Maps a completed [PvtResult] to a 0-100 "reaction-speed alertness" score.
///
/// This is honest, non-diagnostic framing of raw PVT performance — not a
/// medical or sleep-stage measure. Faster mean reaction time raises the
/// score; lapses (RTs over the lapse threshold) and false starts (tapping
/// during the wait phase) subtract a penalty. Dismissal is never gated on
/// this score — see the anti-trap invariant in the phase-6 plan.
int alertnessScore(PvtResult r) {
  if (r.validTaps == 0) return 0;

  final rtComponent =
      (100 * (600 - r.meanRtMs) / (600 - 220)).clamp(0.0, 100.0);
  final penalty = r.lapses * 8 + r.falseStarts * 5;
  final score = (rtComponent - penalty).round();
  return score.clamp(0, 100);
}
