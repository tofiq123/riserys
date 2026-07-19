import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../domain/pvt.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'mission_frame.dart';

enum _PvtPhase { waiting, stimulus }

/// A Psychomotor Vigilance Task (mini-PVT) dismiss mission: alternating
/// "wait" and "tap now" trials that both wake the user and measure a
/// reaction-speed alertness score.
///
/// Anti-trap invariant: this mission ALWAYS completes once
/// `config.trials` valid taps are collected, regardless of the resulting
/// score. A low score is reported via [onResult], never used to block
/// dismissal — see the phase-6 plan's anti-shame red line.
class PvtMission extends StatefulWidget {
  const PvtMission({
    super.key,
    required this.diff,
    required this.onSolved,
    this.onResult,
    this.config, // injectable for tests
    this.nowMs, // injectable millisecond clock for tests
    this.scriptedIsiMs, // injectable deterministic ISI sequence for tests
  });

  final String diff;
  final VoidCallback onSolved;
  final void Function(int alertnessScore)? onResult;
  final PvtConfig? config;
  final int Function()? nowMs;
  final List<int>? scriptedIsiMs;

  @override
  State<PvtMission> createState() => _PvtMissionState();
}

class _PvtMissionState extends State<PvtMission> {
  late final PvtConfig _config = widget.config ?? pvtConfigFor(widget.diff);
  late final int Function() _now =
      widget.nowMs ?? () => DateTime.now().millisecondsSinceEpoch;
  final _rng = Random();

  _PvtPhase _phase = _PvtPhase.waiting;
  int _trialIndex = 0;
  int _currentIsiMs = 0;
  int? _stimulusShownAt;
  final _rts = <int>[];
  int _falseStarts = 0;
  bool _solved = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startWait();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  int _isiFor(int trialIndex) {
    final scripted = widget.scriptedIsiMs;
    if (scripted != null && trialIndex < scripted.length) {
      return scripted[trialIndex];
    }
    final min = _config.isiMinMs;
    final max = _config.isiMaxMs;
    if (max <= min) return min;
    return min + _rng.nextInt(max - min + 1);
  }

  /// Begins (or restarts) the wait phase for the current trial.
  void _startWait() {
    _currentIsiMs = _isiFor(_trialIndex);
    _phase = _PvtPhase.waiting;
    _stimulusShownAt = null;
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: _currentIsiMs), _showStimulus);
  }

  void _showStimulus() {
    if (!mounted) return;
    setState(() {
      _phase = _PvtPhase.stimulus;
      _stimulusShownAt = _now();
    });
  }

  void _tap() {
    if (_solved) return;
    if (_phase == _PvtPhase.waiting) {
      // False start: tapped before the stimulus — no RT, restart this trial.
      _falseStarts++;
      setState(_startWait);
      return;
    }
    final shownAt = _stimulusShownAt ?? _now();
    final rt = _now() - shownAt;
    _rts.add(rt);
    _trialIndex++;
    if (_trialIndex >= _config.trials) {
      _finish();
    } else {
      setState(_startWait);
    }
  }

  void _finish() {
    _timer?.cancel();
    setState(() => _solved = true);
    final result = computePvtResult(
      _rts,
      falseStarts: _falseStarts,
      lapseThresholdMs: _config.lapseThresholdMs,
    );
    widget.onResult?.call(alertnessScore(result));
    widget.onSolved();
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final isStimulus = _phase == _PvtPhase.stimulus;
    return MissionFrame(
      instruction: 'Tap the moment it turns green',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${_rts.length} / ${_config.trials}',
              style: RiseText.mono(
                  size: 14,
                  weight: FontWeight.w500,
                  color: RiseColors.textDim)),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: _tap,
            child: AnimatedContainer(
              duration: disableAnimations
                  ? Duration.zero
                  : const Duration(milliseconds: 150),
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                color: isStimulus ? RiseColors.positive : RiseColors.surface2,
                borderRadius: BorderRadius.circular(RiseRadii.lg),
                border:
                    isStimulus ? null : Border.all(color: RiseColors.border),
                boxShadow: isStimulus ? RiseShadows.primary : null,
              ),
              alignment: Alignment.center,
              child: Text(
                isStimulus ? 'TAP!' : 'Wait…',
                style: RiseText.mono(
                  size: 20,
                  weight: FontWeight.w600,
                  color:
                      isStimulus ? RiseColors.primaryText : RiseColors.textDim,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
