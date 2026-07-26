import 'package:flutter/widgets.dart';

import '../theme/typography.dart';

/// The small caps date line above a tab title ("SATURDAY · JUL 26") — a daily
/// freshness cue shared by the story tabs (Crew, Stats), leaving Home to its
/// next-alarm headline.
class DateEyebrow extends StatelessWidget {
  const DateEyebrow({super.key, this.now});

  /// Test seam; defaults to the current local date.
  final DateTime? now;

  static const _days = [
    'MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY',
  ];
  static const _months = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];

  @override
  Widget build(BuildContext context) {
    final d = (now ?? DateTime.now()).toLocal();
    final label =
        '${_days[d.weekday - 1]} · ${_months[d.month - 1]} ${d.day}';
    return Text(label, style: RiseText.sectionLabel);
  }
}
