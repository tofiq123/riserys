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
    const on = Duration(milliseconds: 420);
    const gap = Duration(milliseconds: 180);
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
    });
    _play();
  }

  void _tap(int pad) {
    if (!_accepting || _inputPos >= _seq.length) return;
    if (pad == _seq[_inputPos]) {
      _inputPos++;
      if (_inputPos >= _seq.length) widget.onSolved();
    } else {
      _replay(); // wrong — show it again
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
                    color: _flashIndex == i
                        ? RiseColors.accent
                        : RiseColors.surface2,
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
}
