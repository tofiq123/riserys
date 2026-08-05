import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'mission_frame.dart';

int memoryLengthFor(String diff) {
  switch (diff) {
    case 'hard':
      return 5;
    case 'medium':
      return 4;
    default:
      return 3;
  }
}

/// A random pad sequence (pads 0..3). Pass [rng] for determinism in tests.
List<int> generateSequence(int length, [Random? rng]) {
  final r = rng ?? Random();
  return List.generate(length, (_) => r.nextInt(4));
}

class MemoryMission extends StatefulWidget {
  const MemoryMission({
    super.key,
    required this.diff,
    required this.onSolved,
    this.sequence, // injectable for tests
  });

  final String diff;
  final VoidCallback onSolved;
  final List<int>? sequence;

  @override
  State<MemoryMission> createState() => _MemoryMissionState();
}

class _MemoryMissionState extends State<MemoryMission> {
  late List<int> _seq;
  int _flashIndex = -1; // lit pad during playback; -1 = none
  int _inputPos = 0;
  bool _accepting = false;
  final _timers = <Timer>[];

  /// Which pad was just tapped during recall, and whether it was correct —
  /// drives a brief color flash so every tap visibly registers, right or
  /// wrong. null = no pending feedback.
  int? _tapFeedback;
  bool _tapCorrect = false;

  static const _tapFeedbackDuration = Duration(milliseconds: 350);

  @override
  void initState() {
    super.initState();
    _seq = widget.sequence ?? generateSequence(memoryLengthFor(widget.diff));
    _play();
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    super.dispose();
  }

  void _play() {
    _accepting = false;
    _inputPos = 0;
    const on = Duration(milliseconds: 650);
    const gap = Duration(milliseconds: 280);
    var t = Duration.zero;
    for (var i = 0; i < _seq.length; i++) {
      final lit = _seq[i];
      _timers.add(Timer(t, () {
        if (mounted) setState(() => _flashIndex = lit);
      }));
      t += on;
      _timers.add(Timer(t, () {
        if (mounted) setState(() => _flashIndex = -1);
      }));
      t += gap;
    }
    _timers.add(Timer(t, () {
      if (mounted) setState(() => _accepting = true);
    }));
  }

  void _replay() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    setState(() {
      _flashIndex = -1;
      _accepting = false;
      _inputPos = 0;
      _tapFeedback = null;
    });
    _play();
  }

  void _tap(int pad) {
    if (!_accepting || _inputPos >= _seq.length) return;
    final correct = pad == _seq[_inputPos];
    setState(() {
      _tapFeedback = pad;
      _tapCorrect = correct;
    });
    if (correct) {
      _inputPos++;
      if (_inputPos >= _seq.length) {
        widget.onSolved();
        return;
      }
      // Clear the flash before the next tap's own feedback would show —
      // the mission isn't done yet, so leave time to see it registered.
      _timers.add(Timer(_tapFeedbackDuration, () {
        if (mounted) setState(() => _tapFeedback = null);
      }));
    } else {
      // Let the red flash actually be seen before the sequence replays.
      _timers.add(Timer(_tapFeedbackDuration, () {
        if (mounted) _replay();
      }));
    }
  }

  @override
  Widget build(BuildContext context) {
    return MissionFrame(
      instruction: _accepting ? 'Repeat the sequence' : 'Watch carefully…',
      child: SizedBox(
        width: 200,
        child: GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          children: [
            for (var i = 0; i < 4; i++)
              GestureDetector(
                key: ValueKey('mem-pad-$i'),
                onTap: () => _tap(i),
                child: Container(
                  decoration: BoxDecoration(
                    color: _tileColor(i),
                    borderRadius: BorderRadius.circular(RiseRadii.base),
                    border: Border.all(color: RiseColors.border),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Playback lit pad wins over tap feedback (they never overlap in
  /// practice — feedback only shows during recall, playback only before it).
  Color _tileColor(int i) {
    if (_flashIndex == i) return RiseColors.accent;
    if (_tapFeedback == i) {
      return _tapCorrect ? RiseColors.positive : RiseColors.danger;
    }
    return RiseColors.surface2;
  }
}
