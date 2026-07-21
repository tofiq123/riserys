import 'dart:math';

import 'package:flutter/material.dart';

import '../components/rise_buttons.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'mission_frame.dart';

typedef MathProblem = ({String prompt, int answer});

/// A random arithmetic problem scaled by difficulty. Pass [rng] for
/// determinism in tests.
MathProblem generateMathProblem(String diff, [Random? rng]) {
  final r = rng ?? Random();
  switch (diff) {
    case 'hard':
      final a = 3 + r.nextInt(11); // 3..13
      final b = 3 + r.nextInt(11);
      return (prompt: '$a × $b', answer: a * b);
    case 'medium':
      final a = 10 + r.nextInt(40); // 10..49
      final b = 10 + r.nextInt(40);
      return (prompt: '$a + $b', answer: a + b);
    default: // easy
      final a = 2 + r.nextInt(18); // 2..19
      final b = 2 + r.nextInt(18);
      return (prompt: '$a + $b', answer: a + b);
  }
}

class MathMission extends StatefulWidget {
  const MathMission({
    super.key,
    required this.diff,
    required this.onSolved,
    this.problem, // injectable for tests
  });

  final String diff;
  final VoidCallback onSolved;
  final MathProblem? problem;

  @override
  State<MathMission> createState() => _MathMissionState();
}

class _MathMissionState extends State<MathMission> {
  late MathProblem _p;
  final _controller = TextEditingController();
  bool _wrong = false;
  bool _solved = false;

  @override
  void initState() {
    super.initState();
    _p = widget.problem ?? generateMathProblem(widget.diff);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_solved) return;
    if (int.tryParse(_controller.text.trim()) == _p.answer) {
      _solved = true;
      widget.onSolved();
      return;
    }
    setState(() {
      _wrong = true;
      _controller.clear();
      // A fresh problem (when not injected) so guessing can't brute-force it.
      _p = widget.problem ?? generateMathProblem(widget.diff);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MissionFrame(
      instruction: 'Solve to dismiss',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${_p.prompt} = ?',
              style: RiseText.mono(size: 40, weight: FontWeight.w500)),
          const SizedBox(height: 16),
          SizedBox(
            width: 160,
            child: TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: RiseText.mono(size: 24),
              cursorColor: RiseColors.primary,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: '?',
                filled: true,
                fillColor: RiseColors.surface2,
                errorText: _wrong ? 'Try again' : null,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(RiseRadii.base),
                  borderSide: BorderSide(
                      color: _wrong ? RiseColors.danger : RiseColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(RiseRadii.base),
                  borderSide: BorderSide(color: RiseColors.primary),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          PrimaryButton(label: 'Check', onPressed: _submit),
        ],
      ),
    );
  }
}
