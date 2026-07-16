import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Common presentation for a wake mission: a bold instruction above the
/// interactive area.
class MissionFrame extends StatelessWidget {
  const MissionFrame({super.key, required this.instruction, required this.child});

  final String instruction;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(instruction,
            textAlign: TextAlign.center,
            style: RiseText.body
                .copyWith(color: RiseColors.textDim, fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        child,
      ],
    );
  }
}
