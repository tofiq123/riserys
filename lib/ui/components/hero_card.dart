import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

/// The one inverse-ground surface per tab: a near-black card in the light
/// theme (near-white in dark — same inversion the crew-score card uses) that
/// carries the tab's headline. Everything around it stays quiet, so each
/// screen has exactly one place the eye lands first.
class HeroCard extends StatelessWidget {
  const HeroCard({
    super.key,
    this.eyebrow,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(22, 20, 22, 22),
  });

  /// Small caps line above the content (callers pass it already uppercased).
  final String? eyebrow;

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: RiseColors.primary,
        borderRadius: BorderRadius.circular(RiseRadii.lg),
        boxShadow: RiseShadows.primary,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (eyebrow != null) ...[
            Opacity(
              opacity: 0.65,
              child: Text(eyebrow!,
                  style: RiseText.sectionLabel
                      .copyWith(color: RiseColors.primaryText)),
            ),
            const SizedBox(height: 12),
          ],
          child,
        ],
      ),
    );
  }
}

/// Filled button for the hero's inverse ground: light on the dark card (and
/// dark on the light card in dark theme). The hero's single call to action.
class HeroButton extends StatelessWidget {
  const HeroButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onPressed == null ? 0.55 : 1,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Container(
          alignment: Alignment.center,
          constraints: const BoxConstraints(minHeight: 46),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: RiseColors.primaryText,
            borderRadius: BorderRadius.circular(RiseRadii.sm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 17, color: RiseColors.primary),
                const SizedBox(width: 8),
              ],
              Text(label,
                  style: RiseText.body.copyWith(
                      color: RiseColors.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Quiet text action on the hero ground, for the secondary path.
class HeroGhostButton extends StatelessWidget {
  const HeroGhostButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: Container(
        alignment: Alignment.center,
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Opacity(
          opacity: 0.8,
          child: Text(label,
              style: RiseText.body.copyWith(
                  color: RiseColors.primaryText,
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5)),
        ),
      ),
    );
  }
}
