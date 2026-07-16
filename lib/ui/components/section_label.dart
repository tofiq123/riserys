import 'package:flutter/widgets.dart';

import '../theme/typography.dart';

/// 11px uppercase semibold label with 0.1em tracking, e.g. "YOUR ALARMS".
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: RiseText.sectionLabel);
}
