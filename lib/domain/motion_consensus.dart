/// Post-dismissal *sustained-motion* consensus — the strong "they got up and
/// moved" signal for the opt-in smart wake-check (Phase 11).
///
/// Pure and injectable: it decides, from a series of cumulative pedometer
/// readings sampled across the post-dismissal window, whether the user showed
/// *sustained* motion (got up and walked) versus stayed still. The actual
/// pedometer subscription over the window is a thin, device-only wrapper
/// ([MotionSensor]) kept separate so this decision logic stays headlessly
/// testable.
class MotionConsensus {
  const MotionConsensus._();

  /// Steps that must accumulate across the window to count as "got up and
  /// moved". Chosen conservatively: a couple of steps can just be a shift in
  /// bed, but a dozen cumulative steps over the (minutes-long) window is a
  /// deliberate walk. This is the threshold above which we trust the "they got
  /// up" signal. Tunable — see the Phase 11 judgment calls.
  static const int defaultStepThreshold = 12;

  /// Whether [cumulativeSamples] (pedometer step counts, oldest → newest) show
  /// sustained motion: at least [threshold] steps accumulated between the first
  /// and last reading.
  ///
  /// Pure. Conservative by construction — every "not enough evidence" case
  /// returns false so the caller re-challenges rather than trusting a maybe:
  ///  * fewer than two samples (nothing to compare) → false;
  ///  * a non-positive delta, including a counter reset/reboot mid-window →
  ///    false.
  static bool sustained(
    List<int> cumulativeSamples, {
    int threshold = defaultStepThreshold,
  }) {
    if (cumulativeSamples.length < 2) return false;
    final delta = cumulativeSamples.last - cumulativeSamples.first;
    if (delta <= 0) return false;
    return delta >= threshold;
  }

  /// The net steps accumulated across [cumulativeSamples] (first → last),
  /// clamped at zero so a counter reset never reads as negative movement.
  /// Exposed for logging/telemetry; the decision itself uses [sustained].
  static int netSteps(List<int> cumulativeSamples) {
    if (cumulativeSamples.length < 2) return 0;
    final delta = cumulativeSamples.last - cumulativeSamples.first;
    return delta < 0 ? 0 : delta;
  }
}
