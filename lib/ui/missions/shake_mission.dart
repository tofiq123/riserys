import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../components/slide_to_wake.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'mission_frame.dart';

/// Cumulative *active-shaking* milliseconds required to dismiss, scaled by
/// difficulty. Unlike a discrete peak count (which a few half-asleep flicks can
/// satisfy), this demands the phone keep moving: progress only accrues while
/// shaking and resets the moment the motion stops for too long, so a couple of
/// flicks never complete it.
int shakeRequiredMsFor(String diff) {
  switch (diff) {
    case 'hard':
      return 7000;
    case 'medium':
      return 5000;
    default:
      return 3000;
  }
}

/// Standard gravity in m/s^2 — [accelerometerEventStream] readings include
/// gravity, so a still phone reads ~1 g on the magnitude below.
const double _gravity = 9.80665;

/// The g-force magnitude of a raw accelerometer reading (gravity included).
/// A phone at rest is ~1.0; a brisk shake spikes well above the threshold.
double gForceMagnitude(double x, double y, double z) =>
    sqrt(x * x + y * y + z * z) / _gravity;

/// Pure, headlessly-testable *sustained*-shake accumulator. Fed one time-sliced
/// sample at a time as `(gForceMagnitude, dtMs)` — the g-force of the reading
/// and the elapsed milliseconds since the previous sample.
///
/// Progress ([activeMs]) accrues only while the phone is actually moving: a
/// sample above [gForceThreshold] credits its whole time slice, and a brief
/// sub-threshold trough between two shake swings (shorter than [graceMs]) still
/// counts — so the natural dip as the phone reverses direction does not stall a
/// steady shake. But once the phone has been calm for [graceMs] the rhythm is
/// considered broken and progress resets to zero: a couple of isolated flicks
/// never accumulate enough, and a real pause wipes cheaply-earned progress.
/// Completes at [requiredMs].
///
/// [graceMs] is deliberately short (about one shake half-cycle) so a single
/// flick only buys that little credit before the streak lapses — you have to
/// keep the rhythm going. A sampling gap of [graceMs] or longer (e.g. a dropped
/// stream on app resume) is likewise treated as a lapse rather than crediting
/// the whole unobserved span, so a lone reading can never over-count.
///
/// This is the whole difficulty story — feed it steady shaking and it fills at
/// roughly wall-clock rate; stop shaking and it resets to zero.
class SustainedShakeDetector {
  SustainedShakeDetector({
    required this.requiredMs,
    this.gForceThreshold = 2.2,
    this.graceMs = 350,
  });

  /// Per-sample "the phone is moving right now" gate. Lower than a discrete
  /// peak-detector's threshold because here we sample the *whole* motion, not
  /// just its crest.
  final double gForceThreshold;

  /// Cumulative active-shaking time (ms) needed to complete.
  final int requiredMs;

  /// The longest calm stretch still treated as continuous shaking. Being still
  /// (or a sampling gap) of this length or longer breaks the rhythm and resets
  /// progress.
  final int graceMs;

  int _activeMs = 0;
  int _calmMs = 0;
  bool _moving = false; // has a shake started the current streak?

  /// Cumulative active-shaking milliseconds, clamped to [requiredMs].
  int get activeMs => _activeMs > requiredMs ? requiredMs : _activeMs;

  /// 0..1 fill of the progress meter.
  double get progress =>
      requiredMs <= 0 ? 1.0 : (activeMs / requiredMs).clamp(0.0, 1.0);

  /// Whether enough active shaking has accumulated to dismiss.
  bool get isComplete => _activeMs >= requiredMs;

  /// Feeds one `(magnitude, dtMs)` slice. Returns true once [isComplete].
  bool onSample(double magnitude, int dtMs) {
    if (dtMs < 0) dtMs = 0;
    // A gap at least as long as the grace window carries no evidence of motion
    // across it: the streak lapses and this lone reading starts fresh, crediting
    // nothing on its own.
    if (dtMs >= graceMs) {
      _moving = magnitude > gForceThreshold;
      _calmMs = 0;
      _activeMs = 0;
      return isComplete;
    }
    if (magnitude > gForceThreshold) {
      _moving = true;
      _calmMs = 0;
      _activeMs += dtMs;
    } else {
      _calmMs += dtMs;
      if (_moving && _calmMs < graceMs) {
        _activeMs += dtMs; // brief trough between swings — still shaking
      } else if (_calmMs >= graceMs) {
        _moving = false;
        _activeMs = 0; // held still past the grace window — rhythm broke
      }
    }
    return isComplete;
  }
}

/// A "shake it off" dismiss mission: the user must keep the phone shaking for a
/// cumulative active-shaking window ([SustainedShakeDetector.requiredMs]),
/// scaled by difficulty. A steady shake fills the meter; a couple of flicks or
/// a pause resets it — harder to fake than a discrete peak count.
///
/// Anti-trap invariant: reaching the window ALWAYS dismisses, and nothing else
/// gates dismissal. The accelerometer needs no runtime permission, but a device
/// with a broken/absent sensor (the stream errors, or nothing is sensed within
/// [fallbackAfter]) must still be escapable — so, like the walk-it-off mission,
/// this offers a slide-to-wake fallback rather than trapping the user.
///
/// [sampleStream], [nowMs] and [fallbackAfter] are injectable so the
/// accumulation/threshold logic and the fallback path can be driven
/// deterministically in tests without the platform sensor.
class ShakeMission extends StatefulWidget {
  const ShakeMission({
    super.key,
    required this.diff,
    required this.onSolved,
    this.requiredMs, // injectable for tests
    this.sampleStream, // injectable accelerometer samples for tests
    this.nowMs, // injectable millisecond clock for tests
    this.gForceThreshold, // injectable per-sample gate for tests
    this.fallbackAfter = const Duration(seconds: 40),
  });

  final String diff;
  final VoidCallback onSolved;
  final int? requiredMs;
  final Stream<({double x, double y, double z})>? sampleStream;
  final int Function()? nowMs;
  final double? gForceThreshold;
  final Duration fallbackAfter;

  @override
  State<ShakeMission> createState() => _ShakeMissionState();
}

class _ShakeMissionState extends State<ShakeMission> {
  late final int Function() _now =
      widget.nowMs ?? () => DateTime.now().millisecondsSinceEpoch;
  late final SustainedShakeDetector _detector = SustainedShakeDetector(
    requiredMs: widget.requiredMs ?? shakeRequiredMsFor(widget.diff),
    gForceThreshold: widget.gForceThreshold ?? 2.2,
  );

  StreamSubscription<({double x, double y, double z})>? _sub;
  Timer? _fallbackTimer;
  int? _lastNow;
  double _progress = 0;
  bool _solved = false;

  /// True once we should surface the slide-to-wake escape (the sensor errored
  /// or nothing was sensed within [ShakeMission.fallbackAfter]).
  bool _fallback = false;

  @override
  void initState() {
    super.initState();
    final stream = widget.sampleStream ??
        accelerometerEventStream().map((e) => (x: e.x, y: e.y, z: e.z));
    _sub = stream.listen(_onSample, onError: (_) => _showFallback());
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

  void _onSample(({double x, double y, double z}) s) {
    if (_solved) return;
    final now = _now();
    final dt = _lastNow == null ? 0 : now - _lastNow!;
    _lastNow = now;
    final done = _detector.onSample(gForceMagnitude(s.x, s.y, s.z), dt);
    if (mounted && _detector.progress != _progress) {
      setState(() => _progress = _detector.progress);
    }
    if (done && !_solved) {
      _solved = true;
      _fallbackTimer?.cancel();
      widget.onSolved();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_fallback) {
      return MissionFrame(
        instruction: "Can't read motion on this device",
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

    final pct = (_progress * 100).round();
    return MissionFrame(
      instruction: _progress <= 0
          ? 'Shake your phone — and keep shaking'
          : 'Keep shaking until it fills',
      child: SizedBox(
        width: 150,
        height: 150,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 150,
              height: 150,
              child: CircularProgressIndicator(
                value: _progress,
                strokeWidth: 10,
                backgroundColor: RiseColors.surface2,
                valueColor: AlwaysStoppedAnimation(RiseColors.primary),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.vibration, size: 40, color: RiseColors.primary),
                const SizedBox(height: 8),
                Text('$pct%',
                    style: RiseText.mono(
                        size: 26,
                        weight: FontWeight.w600,
                        color: RiseColors.text)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
