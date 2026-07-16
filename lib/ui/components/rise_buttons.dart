import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, required this.onPressed, this.icon});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return _BaseButton(
      onPressed: onPressed,
      background: RiseColors.primary,
      border: null,
      shadow: RiseShadows.primary,
      child: _content(label, icon, RiseColors.primaryText),
    );
  }
}

class SecondaryButton extends StatelessWidget {
  const SecondaryButton({super.key, required this.label, required this.onPressed, this.icon});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return _BaseButton(
      onPressed: onPressed,
      background: RiseColors.card,
      border: RiseColors.border,
      shadow: const [],
      child: _content(label, icon, RiseColors.text),
    );
  }
}

class GhostButton extends StatelessWidget {
  const GhostButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Text(label,
            style: RiseText.body.copyWith(
                color: RiseColors.accent, fontWeight: FontWeight.w600, fontSize: 13)),
      ),
    );
  }
}

Widget _content(String label, IconData? icon, Color color) {
  final text = Text(label,
      style: RiseText.body.copyWith(color: color, fontWeight: FontWeight.w600, fontSize: 15));
  if (icon == null) return text;
  return Row(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [Icon(icon, size: 16, color: color), const SizedBox(width: 8), text],
  );
}

class _BaseButton extends StatelessWidget {
  const _BaseButton({
    required this.onPressed,
    required this.background,
    required this.border,
    required this.shadow,
    required this.child,
  });

  final VoidCallback? onPressed;
  final Color background;
  final Color? border;
  final List<BoxShadow> shadow;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(RiseRadii.base),
            border: border == null ? null : Border.all(color: border!),
            boxShadow: shadow,
          ),
          child: child,
        ),
      ),
    );
  }
}
