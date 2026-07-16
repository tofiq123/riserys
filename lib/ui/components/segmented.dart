import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

class SegmentedControl<T> extends StatelessWidget {
  const SegmentedControl({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  final List<({T value, String label})> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: RiseColors.surface2,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: RiseColors.border),
      ),
      child: Row(
        children: [
          for (final s in segments)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(s.value),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: s.value == selected ? RiseColors.primary : const Color(0x00000000),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    s.label,
                    style: RiseText.body.copyWith(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: s.value == selected ? RiseColors.primaryText : RiseColors.textDim,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
