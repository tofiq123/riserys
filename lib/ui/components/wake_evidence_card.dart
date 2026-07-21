import 'package:flutter/material.dart';

import '../../domain/wake_evidence.dart';
import 'rise_card.dart';
import 'section_label.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// The wake-evidence "user card": a warm, self-explaining read on how the user
/// woke this morning — a verdict, a 0–100 confidence meter, and the individual
/// signals that fed it (timing, how they got up, snoozes, left-home, alertness).
///
/// Dumb by design: it renders a pre-computed [WakeEvidence] (see
/// `wakeEvidenceProvider`) so it's trivial to preview and test. Colours come
/// from the live [RiseColors] palette, so this is built at runtime (never const).
class WakeEvidenceCard extends StatelessWidget {
  const WakeEvidenceCard({super.key, required this.evidence});

  final WakeEvidence evidence;

  @override
  Widget build(BuildContext context) {
    final accent = _toneColor(evidence.tone);
    return RiseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SectionLabel('How you woke up'),
              const Spacer(),
              _scoreBadge(accent),
            ],
          ),
          const SizedBox(height: 14),
          Text(evidence.verdict,
              style: RiseText.title.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(evidence.blurb,
              style: RiseText.caption.copyWith(color: RiseColors.textDim)),
          const SizedBox(height: 14),
          _meter(accent),
          const SizedBox(height: 16),
          for (var i = 0; i < evidence.signals.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _signalRow(evidence.signals[i]),
          ],
        ],
      ),
    );
  }

  /// The composite score as a mono numeral with a tone dot — fits the app's
  /// monospace-numerals identity.
  Widget _scoreBadge(Color accent) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text('${evidence.score}',
              style: RiseText.mono(size: 20, weight: FontWeight.w600)),
          const SizedBox(width: 2),
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text('/100',
                style: RiseText.mono(size: 11, color: RiseColors.textFaint)),
          ),
        ],
      );

  /// A thin confidence meter: a faint full-width track with a tone-tinted fill
  /// proportional to the score.
  Widget _meter(Color accent) => ClipRRect(
        borderRadius: BorderRadius.circular(RiseRadii.pill),
        child: Stack(
          children: [
            Container(height: 6, color: RiseColors.divider),
            LayoutBuilder(
              builder: (_, c) => Container(
                height: 6,
                width: c.maxWidth * (evidence.score / 100),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(RiseRadii.pill),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _signalRow(EvidenceSignal s) {
    final tone = _toneColor(s.tone);
    return Row(
      children: [
        Icon(_toneIcon(s.tone), size: 16, color: tone),
        const SizedBox(width: 10),
        Text(s.label,
            style: RiseText.body.copyWith(fontWeight: FontWeight.w600)),
        const Spacer(),
        Flexible(
          child: Text(s.detail,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: RiseText.caption.copyWith(color: RiseColors.textDim)),
        ),
      ],
    );
  }

  static Color _toneColor(EvidenceTone t) => switch (t) {
        EvidenceTone.good => RiseColors.positive,
        EvidenceTone.warn => RiseColors.waking,
        EvidenceTone.bad => RiseColors.danger,
        EvidenceTone.neutral => RiseColors.textFaint,
      };

  static IconData _toneIcon(EvidenceTone t) => switch (t) {
        EvidenceTone.good => Icons.check_circle_outline,
        EvidenceTone.warn => Icons.error_outline,
        EvidenceTone.bad => Icons.remove_circle_outline,
        EvidenceTone.neutral => Icons.radio_button_unchecked,
      };
}
