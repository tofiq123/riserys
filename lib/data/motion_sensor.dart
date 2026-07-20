import 'dart:async';

import 'package:pedometer/pedometer.dart';

import '../domain/motion_consensus.dart';

/// DEVICE-ONLY, best-effort wrapper that samples the platform pedometer across
/// the post-dismissal window and reports whether the user showed sustained
/// motion. Deliberately thin: all the decision logic lives in the pure
/// [MotionConsensus]; this only owns the subscription + windowing, so it can be
/// driven in tests with an injected stream and never needs the real sensor.
///
/// Reuses the already-added `pedometer` plugin — the same cumulative step
/// stream the walk mission subscribes to. No new plugin, no native change.
class MotionSensor {
  const MotionSensor({this.stepStream});

  /// Injectable cumulative step-count stream (defaults to the platform
  /// pedometer). Emissions are the device's running step counter, exactly as in
  /// the walk mission.
  final Stream<int>? stepStream;

  /// Collects step readings for [window] then decides via [MotionConsensus].
  ///
  /// Best-effort and fail-safe: on a stream error, or too few readings to
  /// judge, it returns false → the caller treats "unknown" as "still" and
  /// re-challenges. Never throws. The window is bounded by a timer, so a stream
  /// that keeps emitting (or never emits) still resolves.
  Future<bool> sensedSustainedMotion(
    Duration window, {
    int threshold = MotionConsensus.defaultStepThreshold,
  }) async {
    final stream = stepStream ?? Pedometer.stepCountStream.map((e) => e.steps);
    final samples = <int>[];
    final done = Completer<void>();
    void finish() {
      if (!done.isCompleted) done.complete();
    }

    final sub = stream.listen(
      samples.add,
      onError: (_) => finish(), // sensor unavailable → resolve as "unknown"
      cancelOnError: true,
    );
    final timer = Timer(window, finish);
    try {
      await done.future;
    } finally {
      timer.cancel();
      await sub.cancel();
    }
    return MotionConsensus.sustained(samples, threshold: threshold);
  }
}
