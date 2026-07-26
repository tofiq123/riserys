import 'wake_event.dart';

/// Which way a run of alertness scores is heading over time.
enum AlertnessTrend { rising, steady, easing, insufficient }

/// The mean of the non-null alertness scores across [events], rounded to the
/// nearest integer; null when no event carries a score.
int? averageAlertness(List<WakeEvent> events) {
  final scores = [
    for (final e in events)
      if (e.alertnessScore != null) e.alertnessScore!
  ];
  if (scores.isEmpty) return null;
  final sum = scores.fold<int>(0, (a, b) => a + b);
  return (sum / scores.length).round();
}

/// A neutral, non-judgemental descriptor for an alertness [score]. Purely
/// informational — never a medical, diagnostic, or "abnormal" label.
String alertnessBand(int score) {
  if (score >= 80) return 'sharp';
  if (score >= 50) return 'steady';
  return 'groggy';
}

/// Fewest scores needed before a trend reads as anything but insufficient.
const int kMinTrendScores = 4;

/// Compares the most-recent half of [scores] (oldest first) against the
/// earliest half. A change of at least [thresholdPoints] flags rising or
/// easing; a smaller change is steady. Pure; returns [AlertnessTrend.insufficient]
/// below [kMinTrendScores] scores.
///
/// "Easing" is deliberately gentle wording: alertness dipping is information,
/// not a failing.
AlertnessTrend alertnessTrendOf(List<int> scores, {int thresholdPoints = 5}) {
  if (scores.length < kMinTrendScores) return AlertnessTrend.insufficient;
  final half = scores.length ~/ 2;
  final earlier = scores.take(half);
  final recent = scores.skip(scores.length - half);
  final earlierMean = earlier.reduce((a, b) => a + b) / earlier.length;
  final recentMean = recent.reduce((a, b) => a + b) / recent.length;
  final delta = recentMean - earlierMean;
  if (delta >= thresholdPoints) return AlertnessTrend.rising;
  if (delta <= -thresholdPoints) return AlertnessTrend.easing;
  return AlertnessTrend.steady;
}
