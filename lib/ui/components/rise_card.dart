import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// White surface with a 1px border and the two-layer card shadow — the base
/// container for every card in the app.
class RiseCard extends StatelessWidget {
  const RiseCard({
    super.key,
    required this.child,
    this.padding,
    this.radius = RiseRadii.lg,
  });

  final Widget child;
  final EdgeInsets? padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(RiseSpacing.cardPad),
      decoration: BoxDecoration(
        color: RiseColors.card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: RiseColors.border),
        boxShadow: RiseShadows.card,
      ),
      child: child,
    );
  }
}
