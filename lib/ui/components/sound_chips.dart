import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

class SoundChips extends StatelessWidget {
  const SoundChips({
    super.key,
    required this.sounds,
    required this.selected,
    required this.onChanged,
    this.locked = const {},
  });

  final List<String> sounds;
  final String selected;
  final ValueChanged<String> onChanged;

  /// Labels shown with a small lock glyph (a premium-gated option). Tapping a
  /// locked chip still calls [onChanged] — the caller decides to route to the
  /// paywall instead of selecting. Default empty → unchanged behaviour.
  final Set<String> locked;

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
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (locked.contains(s)) ...[
                    Icon(Icons.lock_outline,
                        size: 13,
                        color: s == selected
                            ? RiseColors.primaryText
                            : RiseColors.textDim),
                    const SizedBox(width: 5),
                  ],
                  Text(
                    s,
                    style: RiseText.body.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: s == selected ? RiseColors.primaryText : RiseColors.text,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
