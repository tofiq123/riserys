import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

class RiseSwitch extends StatelessWidget {
  const RiseSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: Container(
        width: 46,
        height: 28,
        decoration: BoxDecoration(
          color: value ? RiseColors.primary : RiseColors.border,
          borderRadius: BorderRadius.circular(RiseRadii.pill),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 22,
            height: 22,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            // Thumb is the raised-surface token (white in light — byte-identical
            // to before — dark in the dark theme) so it stays legible against
            // the light `primary` track when the switch is on in dark mode.
            decoration: BoxDecoration(
              color: RiseColors.card,
              shape: BoxShape.circle,
              boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 2, offset: Offset(0, 1))],
            ),
          ),
        ),
      ),
    );
  }
}
