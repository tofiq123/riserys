import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

/// The compact row action used across the crew surfaces (Accept, Cancel,
/// Copy, …): a small bordered pill whose hit target is always at least
/// 44x44 even though the visual pill stays compact. Disabled (null [onTap])
/// renders at 40% opacity.
class CrewPill extends StatelessWidget {
  const CrewPill(
    this.label, {
    super.key,
    required this.onTap,
    this.filled = false,
    this.danger = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool filled;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final bg = filled ? RiseColors.primary : RiseColors.card;
    final fg = danger
        ? RiseColors.danger
        : filled
            ? RiseColors.primaryText
            : RiseColors.text;
    return Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          alignment: Alignment.center,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(RiseRadii.sm),
              border: filled ? null : Border.all(color: RiseColors.border),
            ),
            child: Text(
              label,
              style: RiseText.body.copyWith(
                color: fg,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
