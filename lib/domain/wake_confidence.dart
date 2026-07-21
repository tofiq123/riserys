/// Multi-signal *awake-confidence* fusion for the opt-in smart wake-check
/// (Phase 11) — how sure we are the user actually stayed up after dismissing,
/// fused from passive post-dismissal signals into a single 0–100 score.
///
/// This never gates a *needed* wake-check: the safety default is to
/// re-challenge (re-ring) whenever confidence is low OR unknown. It can only
/// *satisfy* the stay-up check early when the signals are strong. Getting up
/// (sustained motion) is weighted strongest and is, by design, the only signal
/// that can clear the confident bar on its own — the left-home signal (the
/// opt-in foreground location check) is nearly as strong but deliberately sits
/// just under the bar alone, and the softer signals (app interaction,
/// alertness) add nuance to the score but never substitute for evidence that
/// the user physically got up.
library;

/// The outcome of the smart stay-up check.
enum WakeChallengeDecision {
  /// Strong evidence the user stayed up — the check is satisfied, no re-ring.
  confident,

  /// Low or unknown confidence — fall back to the ordinary wake-check re-ring.
  reCheck,
}

// Signal weights. Motion dominates: interaction + alertness together (40) sit
// below the confident threshold, so the ONLY single soft path to clear it is
// demonstrated sustained motion. Left-home (50) is comparably strong — being
// verifiably beyond the home radius is hard to fake from bed — but alone it
// still sits just under the bar, needing any corroborating signal (in
// practice, leaving home always coincides with motion or app interaction).
// Motion + left-home together saturate: the sum clamps at 100. Tunable — see
// the Phase 11 judgment calls.
const int _motionWeight = 60;
const int _leftHomeWeight = 50;
const int _interactionWeight = 25;
const int _alertnessWeight = 15;

/// Confidence at or above this is treated as "they stayed up".
const int kConfidentThreshold = 60;

/// Confidence, in [0, 100], that the user stayed awake.
///
/// [sustainedMotion] — they got up and moved (the strong signal, from the
/// motion consensus). [appInteracted] — the app saw real interaction during the
/// window. [alertnessScore] — the dismissal's 0–100 PVT alertness, or null when
/// the mission produced none. [leftHome] — the opt-in foreground left-home
/// check (null = unknown/off; see `HomeDepartureChecker`): true is a strong
/// "genuinely up and out" signal; false ("still within the home radius") is
/// NOT evidence of sleep — most people are home when they wake — so it
/// contributes exactly like unknown.
///
/// Missing/unknown signals contribute nothing (false / null → 0), so absent
/// evidence pulls the score *down*, never up — the conservative direction.
int wakeConfidence({
  required bool sustainedMotion,
  required bool appInteracted,
  int? alertnessScore,
  bool? leftHome,
}) {
  var score = 0;
  if (sustainedMotion) score += _motionWeight;
  if (leftHome == true) score += _leftHomeWeight;
  if (appInteracted) score += _interactionWeight;
  if (alertnessScore != null) {
    final a = alertnessScore.clamp(0, 100);
    score += (a * _alertnessWeight / 100).round();
  }
  return score.clamp(0, 100);
}

/// Maps [wakeConfidence] to a [WakeChallengeDecision]. Low OR unknown
/// confidence (below [kConfidentThreshold]) → [WakeChallengeDecision.reCheck];
/// this is the explicit safety default. Only a score at or above the threshold
/// — which, with the current weights, requires demonstrated sustained motion —
/// returns [WakeChallengeDecision.confident].
WakeChallengeDecision wakeChallengeDecision({
  required bool sustainedMotion,
  required bool appInteracted,
  int? alertnessScore,
  bool? leftHome,
}) {
  final confidence = wakeConfidence(
    sustainedMotion: sustainedMotion,
    appInteracted: appInteracted,
    alertnessScore: alertnessScore,
    leftHome: leftHome,
  );
  return confidence >= kConfidentThreshold
      ? WakeChallengeDecision.confident
      : WakeChallengeDecision.reCheck;
}
