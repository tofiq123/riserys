import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

const _letters = ['S', 'M', 'T', 'W', 'T', 'F', 'S']; // index 0=Sun … 6=Sat
const _names = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

/// "Once" / "Weekdays" / "Weekends" / "Every day" / comma list.
String repeatLabel(Set<int> days) {
  if (days.isEmpty) return 'Once';
  final s = (days.toList()..sort()).join(',');
  if (s == '1,2,3,4,5') return 'Weekdays';
  if (s == '0,6') return 'Weekends';
  if (s == '0,1,2,3,4,5,6') return 'Every day';
  return (days.toList()..sort()).map((i) => _names[i]).join(', ');
}

class DayChips extends StatelessWidget {
  const DayChips({super.key, required this.days, this.onToggle, this.compact = false});

  final Set<int> days;
  final ValueChanged<int>? onToggle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 22.0 : 42.0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 0; i < 7; i++)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onToggle == null ? null : () => onToggle!(i),
            child: Container(
              width: compact ? size : null,
              height: size,
              constraints: compact ? null : const BoxConstraints(minWidth: 42),
              alignment: Alignment.center,
              margin: compact ? const EdgeInsets.only(right: 5) : null,
              padding: compact ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: days.contains(i)
                    ? (compact ? RiseColors.accentSoft : RiseColors.primary)
                    : (compact ? const Color(0x00000000) : RiseColors.surface2),
                borderRadius: BorderRadius.circular(compact ? 6 : 11),
              ),
              child: Text(
                _letters[i],
                style: (compact
                        ? RiseText.body.copyWith(fontSize: 10, fontWeight: FontWeight.w600)
                        : RiseText.body.copyWith(fontSize: 13, fontWeight: FontWeight.w600))
                    .copyWith(
                  color: days.contains(i)
                      ? (compact ? RiseColors.accent : RiseColors.primaryText)
                      : (compact ? RiseColors.textFaint : RiseColors.textDim),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
