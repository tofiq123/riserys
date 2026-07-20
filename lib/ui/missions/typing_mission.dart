import 'dart:math';

import 'package:flutter/material.dart';

import '../components/rise_buttons.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'mission_frame.dart';

// Built-in phrases, grouped by difficulty (length/complexity). Kept short and
// wholesome so a groggy user can read and reproduce them.
const List<String> _easyPhrases = [
  'wake up now',
  'rise and shine',
  'up and at it',
  'time to rise',
  'good morning',
];
const List<String> _mediumPhrases = [
  'the early bird gets the worm',
  'today is a brand new day',
  'i am ready to start the day',
  'one small step at a time',
];
const List<String> _hardPhrases = [
  'the secret of getting ahead is getting started',
  'success is small efforts repeated day after day',
  'discipline is choosing what you want most',
];

/// The phrase pool for [diff]. Unknown difficulties fall back to easy.
List<String> phrasesFor(String diff) {
  switch (diff) {
    case 'hard':
      return _hardPhrases;
    case 'medium':
      return _mediumPhrases;
    default:
      return _easyPhrases;
  }
}

/// A random phrase scaled by difficulty. Pass [rng] for determinism in tests.
String pickPhrase(String diff, [Random? rng]) {
  final list = phrasesFor(diff);
  return list[(rng ?? Random()).nextInt(list.length)];
}

/// A "type the phrase" dismiss mission: the user must reproduce a shown phrase
/// (compared case-insensitively and trimmed) to dismiss. Difficulty picks the
/// phrase length/complexity. [phrase] is injectable for deterministic tests.
///
/// Anti-trap invariant: typing the phrase correctly ALWAYS dismisses; a wrong
/// attempt only shows a retry hint, never a lockout.
class TypingMission extends StatefulWidget {
  const TypingMission({
    super.key,
    required this.diff,
    required this.onSolved,
    this.phrase, // injectable for tests
  });

  final String diff;
  final VoidCallback onSolved;
  final String? phrase;

  @override
  State<TypingMission> createState() => _TypingMissionState();
}

class _TypingMissionState extends State<TypingMission> {
  late final String _phrase = widget.phrase ?? pickPhrase(widget.diff);
  final _controller = TextEditingController();
  bool _wrong = false;
  bool _solved = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _matches(String input) =>
      input.trim().toLowerCase() == _phrase.trim().toLowerCase();

  void _submit() {
    if (_solved) return;
    if (_matches(_controller.text)) {
      _solved = true;
      widget.onSolved();
      return;
    }
    setState(() => _wrong = true);
  }

  @override
  Widget build(BuildContext context) {
    return MissionFrame(
      instruction: 'Type this to dismiss',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: RiseColors.surface2,
              borderRadius: BorderRadius.circular(RiseRadii.base),
              border: Border.all(color: RiseColors.border),
            ),
            child: Text(_phrase,
                textAlign: TextAlign.center,
                style:
                    RiseText.title.copyWith(fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            textAlign: TextAlign.center,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.none,
            style: RiseText.body,
            cursorColor: RiseColors.primary,
            onChanged: (_) {
              if (_wrong) setState(() => _wrong = false);
            },
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: 'Type it here',
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
                borderSide: const BorderSide(color: RiseColors.primary),
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
