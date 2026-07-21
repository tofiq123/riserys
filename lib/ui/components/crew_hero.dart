import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

/// The warm, centered hero used by the crew surfaces' empty and signed-out
/// states: an icon in a soft disc, a title, one supporting line, and optional
/// actions underneath. Never a dead end — pass the next step as [actions].
class CrewHero extends StatelessWidget {
  const CrewHero({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.actions = const [],
  });

  final IconData icon;
  final String title;
  final String body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: RiseColors.accentSoft,
            shape: BoxShape.circle,
            border: Border.all(color: RiseColors.border),
          ),
          child: Icon(icon, size: 28, color: RiseColors.textDim),
        ),
        const SizedBox(height: 18),
        Text(
          title,
          textAlign: TextAlign.center,
          style: RiseText.title.copyWith(fontSize: 19),
        ),
        const SizedBox(height: 8),
        Text(
          body,
          textAlign: TextAlign.center,
          style: RiseText.body.copyWith(color: RiseColors.textDim, height: 1.45),
        ),
        for (final action in actions) ...[
          const SizedBox(height: 14),
          action,
        ],
      ],
    );
  }
}
