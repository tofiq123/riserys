import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'mission_frame.dart';

Duration holdDurationFor(String diff) {
  switch (diff) {
    case 'hard':
      return const Duration(seconds: 12);
    case 'medium':
      return const Duration(seconds: 8);
    default:
      return const Duration(seconds: 5);
  }
}

class HoldMission extends StatefulWidget {
  const HoldMission({
    super.key,
    required this.diff,
    required this.onSolved,
    this.holdDuration, // injectable for tests
  });

  final String diff;
  final VoidCallback onSolved;
  final Duration? holdDuration;

  @override
  State<HoldMission> createState() => _HoldMissionState();
}

class _HoldMissionState extends State<HoldMission>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  bool _solved = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: widget.holdDuration ?? holdDurationFor(widget.diff),
    )..addStatusListener((s) {
        if (s == AnimationStatus.completed && !_solved) {
          _solved = true;
          widget.onSolved();
        }
      });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _down() {
    if (_solved) return;
    _c.forward();
  }
  void _up() {
    if (_c.status != AnimationStatus.completed) _c.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return MissionFrame(
      instruction: 'Hold the button until it fills',
      child: GestureDetector(
        onTapDown: (_) => _down(),
        onTapUp: (_) => _up(),
        onTapCancel: _up,
        child: SizedBox(
          width: 140,
          height: 140,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 140,
                  height: 140,
                  child: CircularProgressIndicator(
                    value: _c.value,
                    strokeWidth: 8,
                    backgroundColor: RiseColors.surface2,
                    valueColor: AlwaysStoppedAnimation(RiseColors.primary),
                  ),
                ),
                Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                      color: RiseColors.primary, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Text('HOLD',
                      style: RiseText.mono(
                          size: 16,
                          weight: FontWeight.w700,
                          color: RiseColors.primaryText)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
