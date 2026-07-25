import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

/// A calm, non-alarming "informational, not medical" note — the one reusable
/// home for the wellness red-line. Any surface that shows a wellbeing signal
/// (the PHQ-2 check-in, the Alertness Score) renders this so the framing stays
/// honest and consistent: never a diagnosis, never labelling the person or a
/// score as "abnormal". Default copy suits a screener; pass [text] for a
/// lighter inline note (e.g. under a score).
class RiseDisclaimer extends StatelessWidget {
  const RiseDisclaimer({
    super.key,
    this.text =
        'This is informational only — not a diagnosis or medical advice.',
  });

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(RiseSpacing.cardPad),
      decoration: BoxDecoration(
        color: RiseColors.surface2,
        borderRadius: BorderRadius.circular(RiseRadii.base),
        border: Border.all(color: RiseColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: RiseColors.textDim),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: RiseText.caption)),
        ],
      ),
    );
  }
}
