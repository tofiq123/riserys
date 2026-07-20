import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pedometer/pedometer.dart';

import '../components/slide_to_wake.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'mission_frame.dart';

/// How many steps dismiss the alarm, scaled by difficulty.
int stepTargetFor(String diff) {
  switch (diff) {
    case 'hard':
      return 40;
    case 'medium':
      return 20;
    default:
      return 10;
  }
}

/// Whether the walk goal is met: the delta from the [baseline] step count (the
/// device's cumulative counter when the mission started) to the [current]
/// reading has reached [target]. Pure and headlessly testable.
bool stepGoalReached(int baseline, int current, int target) =>
    current - baseline >= target;

/// A "walk it off" dismiss mission: the user must take [targetSteps] steps,
/// measured by the platform pedometer. Difficulty scales the count.
///
/// The pedometer needs the ACTIVITY_RECOGNITION permission (Android) / motion
/// access (iOS) and a hardware step sensor. If either is missing the step
/// stream errors or never emits — so this mission must never trap: on a stream
/// error, or if no step is detected within [fallbackAfter], it offers a
/// slide-to-wake alternative that still dismisses. Anti-trap invariant holds.
///
/// [stepCountStream] (cumulative step counts) and [fallbackAfter] are injectable
/// so the delta logic and the fallback path can be driven in tests without the
/// platform sensor.
class StepsMission extends StatefulWidget {
  const StepsMission({
    super.key,
    required this.diff,
    required this.onSolved,
    this.targetSteps, // injectable for tests
    this.stepCountStream, // injectable cumulative step counts for tests
    this.fallbackAfter = const Duration(seconds: 30),
  });

  final String diff;
  final VoidCallback onSolved;
  final int? targetSteps;
  final Stream<int>? stepCountStream;
  final Duration fallbackAfter;

  @override
  State<StepsMission> createState() => _StepsMissionState();
}

class _StepsMissionState extends State<StepsMission> {
  late final int _target = widget.targetSteps ?? stepTargetFor(widget.diff);

  StreamSubscription<int>? _sub;
  Timer? _fallbackTimer;
  int? _baseline;
  int _walked = 0;
  bool _solved = false;

  /// True once we should surface the slide-to-wake escape (the sensor errored
  /// or nothing was detected within [fallbackAfter]).
  bool _fallback = false;

  @override
  void initState() {
    super.initState();
    final stream =
        widget.stepCountStream ?? Pedometer.stepCountStream.map((e) => e.steps);
    _sub = stream.listen(_onCount, onError: (_) => _showFallback());
    _fallbackTimer = Timer(widget.fallbackAfter, _showFallback);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _fallbackTimer?.cancel();
    super.dispose();
  }

  void _showFallback() {
    if (_solved || _fallback || !mounted) return;
    setState(() => _fallback = true);
  }

  void _onCount(int steps) {
    if (_solved) return;
    _baseline ??= steps; // first reading anchors the baseline
    final walked = (steps - _baseline!).clamp(0, _target);
    if (walked != _walked && mounted) setState(() => _walked = walked);
    if (stepGoalReached(_baseline!, steps, _target)) {
      _solved = true;
      _fallbackTimer?.cancel();
      widget.onSolved();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_fallback) {
      return MissionFrame(
        instruction: "Can't count steps on this device",
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Slide to wake up instead',
                textAlign: TextAlign.center,
                style: RiseText.caption.copyWith(color: RiseColors.textDim)),
            const SizedBox(height: 14),
            SlideToWake(onWake: widget.onSolved),
          ],
        ),
      );
    }

    final remaining = (_target - _walked).clamp(0, _target);
    final started = _baseline != null;
    return MissionFrame(
      instruction: started
          ? 'Walk $remaining more step${remaining == 1 ? '' : 's'}'
          : 'Get up and start walking',
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
            const Icon(Icons.directions_walk,
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
