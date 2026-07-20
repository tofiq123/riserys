import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'mission_frame.dart';

/// How many shakes dismiss the alarm, scaled by difficulty.
int shakeTargetFor(String diff) {
  switch (diff) {
    case 'hard':
      return 30;
    case 'medium':
      return 20;
    default:
      return 10;
  }
}

/// Standard gravity in m/s^2 — [accelerometerEventStream] readings include
/// gravity, so a still phone reads ~1 g on the magnitude below.
const double _gravity = 9.80665;

/// The g-force magnitude of a raw accelerometer reading (gravity included).
/// A phone at rest is ~1.0; a brisk shake spikes well above the threshold.
double gForceMagnitude(double x, double y, double z) =>
    sqrt(x * x + y * y + z * z) / _gravity;

/// Pure, headlessly-testable shake counter. Fed one accelerometer sample at a
/// time; a sample counts as a *new* shake only when its g-force exceeds
/// [gForceThreshold] AND at least [minGapMs] have passed since the last counted
/// shake. The time gate is what stops a single vigorous shake (many samples
/// over threshold in a row) from inflating the count.
class ShakeDetector {
  ShakeDetector({this.gForceThreshold = 2.7, this.minGapMs = 400});

  /// Classic ShakeDetector threshold (Square's Seismic uses 2.7 g).
  final double gForceThreshold;

  /// Minimum spacing between two counted shakes.
  final int minGapMs;

  int _count = 0;
  int? _lastShakeMs;

  int get count => _count;

  /// Feeds one sample. Returns true iff it registered a new shake.
  bool onSample(double x, double y, double z, int nowMs) {
    if (gForceMagnitude(x, y, z) <= gForceThreshold) return false;
    if (_lastShakeMs != null && nowMs - _lastShakeMs! < minGapMs) return false;
    _lastShakeMs = nowMs;
    _count++;
    return true;
  }
}

/// A "shake it off" dismiss mission: the user must physically shake the phone
/// [targetShakes] times. Difficulty scales the count.
///
/// Anti-trap invariant: reaching the shake count ALWAYS dismisses; nothing else
/// gates dismissal. The accelerometer needs no runtime permission, so there is
/// no permission-denied dead end here.
///
/// [sampleStream] and [nowMs] are injectable so the counting/threshold logic
/// can be driven deterministically in tests without the platform sensor.
class ShakeMission extends StatefulWidget {
  const ShakeMission({
    super.key,
    required this.diff,
    required this.onSolved,
    this.targetShakes, // injectable for tests
    this.sampleStream, // injectable accelerometer samples for tests
    this.nowMs, // injectable millisecond clock for tests
    this.gForceThreshold, // injectable spike threshold for tests
  });

  final String diff;
  final VoidCallback onSolved;
  final int? targetShakes;
  final Stream<({double x, double y, double z})>? sampleStream;
  final int Function()? nowMs;
  final double? gForceThreshold;

  @override
  State<ShakeMission> createState() => _ShakeMissionState();
}

class _ShakeMissionState extends State<ShakeMission> {
  late final int _target = widget.targetShakes ?? shakeTargetFor(widget.diff);
  late final int Function() _now =
      widget.nowMs ?? () => DateTime.now().millisecondsSinceEpoch;
  late final ShakeDetector _detector = ShakeDetector(
      gForceThreshold: widget.gForceThreshold ?? 2.7);

  StreamSubscription<({double x, double y, double z})>? _sub;
  int _count = 0;
  bool _solved = false;

  @override
  void initState() {
    super.initState();
    final stream = widget.sampleStream ??
        accelerometerEventStream()
            .map((e) => (x: e.x, y: e.y, z: e.z));
    _sub = stream.listen(_onSample);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onSample(({double x, double y, double z}) s) {
    if (_solved) return;
    if (!_detector.onSample(s.x, s.y, s.z, _now())) return;
    setState(() => _count = _detector.count);
    if (_count >= _target && !_solved) {
      _solved = true;
      widget.onSolved();
    }
  }

  @override
  Widget build(BuildContext context) {
    final remaining = (_target - _count).clamp(0, _target);
    return MissionFrame(
      instruction: 'Shake your phone $remaining more time'
          '${remaining == 1 ? '' : 's'}',
      child: Container(
        width: 150,
        height: 150,
        decoration: BoxDecoration(
          color: RiseColors.primary,
          borderRadius: BorderRadius.circular(RiseRadii.lg),
          boxShadow: RiseShadows.primary,
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.vibration,
                size: 40, color: RiseColors.primaryText),
            const SizedBox(height: 8),
            Text('$remaining',
                style: RiseText.mono(
                    size: 40,
                    weight: FontWeight.w600,
                    color: RiseColors.primaryText)),
          ],
        ),
      ),
    );
  }
}
