import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

class SoundChips extends StatelessWidget {
  const SoundChips({super.key, required this.sounds, required this.selected, required this.onChanged});

  final List<String> sounds;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in sounds)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(s),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
              decoration: BoxDecoration(
                color: s == selected ? RiseColors.primary : RiseColors.card,
                borderRadius: BorderRadius.circular(RiseRadii.pill),
                border: Border.all(color: s == selected ? const Color(0x00000000) : RiseColors.border),
              ),
              child: Text(
                s,
                style: RiseText.body.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: s == selected ? RiseColors.primaryText : RiseColors.text,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
