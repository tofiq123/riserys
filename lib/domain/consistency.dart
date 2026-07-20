import 'dart:math';

import 'wake_event.dart';
import 'wake_insights.dart' show wakeMinuteOfDay;

/// Minimum completed wake-ups before a consistency score is meaningful. Below
/// this we return null rather than score noise.
const int kMinConsistencyEvents = 5;

/// The wake-time spread (population std-dev, minutes) that maps to a score of 0.
const double _zeroScoreSpread = 90.0;

/// A 0–100 measure of how regular the user's wake time is, or null with fewer
/// than [kMinConsistencyEvents] completed wake-ups. Pure and deterministic.
///
/// Built from the spread of dismissal minute-of-day: a population standard
/// deviation of 0 min scores 100, and [_zeroScoreSpread] min or more scores 0,
/// linear in between. Minute-of-day is treated naively (no midnight wrap),
/// which is fine for a morning-alarm app — see the same note in wake_insights.
int? consistencyScore(List<WakeEvent> events) {
  final mins = <int>[
    for (final e in events)
      if (e.dismissedAt != null) wakeMinuteOfDay(e)!,
  ];
  if (mins.length < kMinConsistencyEvents) return null;

  final mean = mins.reduce((a, b) => a + b) / mins.length;
  final variance =
      mins.map((m) => (m - mean) * (m - mean)).reduce((a, b) => a + b) /
          mins.length;
  final sd = sqrt(variance);
  final score = (100 * (1 - sd / _zeroScoreSpread)).clamp(0.0, 100.0);
  return score.round();
}

/// A neutral, non-judgemental descriptor for a consistency [score]. Purely
/// informational — a low score is data, never a fault to be shamed.
String consistencyBand(int score) {
  if (score >= 80) return 'very steady';
  if (score >= 60) return 'steady';
  if (score >= 40) return 'finding a rhythm';
  return 'variable';
}
