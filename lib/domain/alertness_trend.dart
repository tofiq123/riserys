/// Which way a run of alertness scores is heading over time.
enum AlertnessTrend { rising, steady, easing, insufficient }

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
