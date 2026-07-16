import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'mission_frame.dart';

int tapTargetFor(String diff) {
  switch (diff) {
    case 'hard':
      return 50;
    case 'medium':
      return 30;
    default:
      return 15;
  }
}

class TapMission extends StatefulWidget {
  const TapMission({
    super.key,
    required this.diff,
    required this.onSolved,
    this.targetTaps, // injectable for tests
  });

  final String diff;
  final VoidCallback onSolved;
  final int? targetTaps;

  @override
  State<TapMission> createState() => _TapMissionState();
}

class _TapMissionState extends State<TapMission> {
  int _count = 0;
  late final int _target = widget.targetTaps ?? tapTargetFor(widget.diff);

  void _tap() {
    if (_count >= _target) return;
    setState(() => _count++);
    if (_count >= _target) widget.onSolved();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _target - _count;
    return MissionFrame(
      instruction: 'Tap $remaining more time${remaining == 1 ? '' : 's'}',
      child: GestureDetector(
        onTap: _tap,
        child: Container(
          width: 150,
          height: 150,
          decoration: BoxDecoration(
            color: RiseColors.primary,
            borderRadius: BorderRadius.circular(RiseRadii.lg),
            boxShadow: RiseShadows.primary,
          ),
          alignment: Alignment.center,
          child: Text('$remaining',
              style: RiseText.mono(
                  size: 48,
                  weight: FontWeight.w600,
                  color: RiseColors.primaryText)),
        ),
      ),
    );
  }
}
