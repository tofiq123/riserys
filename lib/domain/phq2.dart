/// The PHQ-2: a short, OPTIONAL wellbeing self-check.
///
/// PHQ-2/9 are public-domain instruments, so no license is required (see the
/// strategic guardrails). Rise uses this ONLY to route a user gently toward
/// professional support — it is never a diagnosis, never labels a person or a
/// score as "abnormal"/"at-risk", and is never auto-triggered or gated behind
/// streaks/engagement. Answers and scores are intentionally NOT persisted
/// (sensitive mental-health data): the check-in is stateless.
library;

/// The two PHQ-2 items, verbatim (public domain).
const List<String> phq2Questions = [
  'Over the last 2 weeks, how often have you been bothered by having little '
      'interest or pleasure in doing things?',
  'Over the last 2 weeks, how often have you been bothered by feeling down, '
      'depressed, or hopeless?',
];

/// The four PHQ-2 response options, in order. Each option's value is its index
/// (0..3): "Not at all" = 0 … "Nearly every day" = 3.
const List<String> phq2Answers = [
  'Not at all',
  'Several days',
  'More than half the days',
  'Nearly every day',
];

/// The standard PHQ-2 cut point. A total of 3 or more is conventionally read as
/// "worth further evaluation" — NOT a diagnosis, and never surfaced as one.
const int phq2Threshold = 3;

/// Sums PHQ-2 answers (each 0..3) into a total of 0..6.
///
/// Pure. Expects exactly two in-range answers; values are clamped defensively
/// so a malformed input can never produce an out-of-range total.
int phq2Score(List<int> answers) {
  var total = 0;
  for (final a in answers) {
    total += a.clamp(0, 3);
  }
  return total;
}

/// Whether [score] reaches the "worth further evaluation" cut point. This is
/// the result screen's routing helper — it selects which warm, non-diagnostic
/// message and how prominently to surface the care resources, nothing more.
bool isAbovePhq2Threshold(int score) => score >= phq2Threshold;
