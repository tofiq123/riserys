import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

/// The dial's current time: 12-hour clock plus AM/PM.
typedef DialTime = ({int hour12, int minute, bool isAm});

/// Big draggable HH:MM picker. Drag a number vertically (~7px per step) to
/// change it, or use the chevrons; values wrap. AM/PM buttons on the right.
class TimeDial extends StatelessWidget {
  const TimeDial({super.key, required this.value, required this.onChanged});

  final DialTime value;
  final ValueChanged<DialTime> onChanged;

  void _setHour(int h) => onChanged((hour12: h, minute: value.minute, isAm: value.isAm));
  void _setMinute(int m) => onChanged((hour12: value.hour12, minute: m, isAm: value.isAm));
  void _setAm(bool am) => onChanged((hour12: value.hour12, minute: value.minute, isAm: am));

  static int _wrapHour(int start, int step) => ((start - 1 + step) % 12 + 12) % 12 + 1;
  static int _wrapMinute(int start, int step) => ((start + step) % 60 + 60) % 60;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _DragNumber(
          value: value.hour12,
          format: (v) => '$v',
          wrap: _wrapHour,
          onChanged: _setHour,
          onIncrement: () => _setHour(value.hour12 % 12 + 1),
          onDecrement: () => _setHour(value.hour12 <= 1 ? 12 : value.hour12 - 1),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(':',
              style: RiseText.mono(size: 58, weight: FontWeight.w500, color: RiseColors.textFaint)),
        ),
        _DragNumber(
          value: value.minute,
          format: (v) => v.toString().padLeft(2, '0'),
          wrap: _wrapMinute,
          onChanged: _setMinute,
          onIncrement: () => _setMinute((value.minute + 1) % 60),
          onDecrement: () => _setMinute((value.minute + 59) % 60),
        ),
        const SizedBox(width: 8),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _AmPmButton(label: 'AM', selected: value.isAm, onTap: () => _setAm(true)),
            const SizedBox(height: 6),
            _AmPmButton(label: 'PM', selected: !value.isAm, onTap: () => _setAm(false)),
          ],
        ),
      ],
    );
  }
}

class _DragNumber extends StatefulWidget {
  const _DragNumber({
    required this.value,
    required this.format,
    required this.wrap,
    required this.onChanged,
    required this.onIncrement,
    required this.onDecrement,
  });

  final int value;
  final String Function(int) format;
  final int Function(int start, int step) wrap;
  final ValueChanged<int> onChanged;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  State<_DragNumber> createState() => _DragNumberState();
}

class _DragNumberState extends State<_DragNumber> {
  double _startY = 0;
  int _startValue = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _chevron(true, widget.onIncrement),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (d) {
            _startY = d.globalPosition.dy;
            _startValue = widget.value;
          },
          onVerticalDragUpdate: (d) {
            // Recompute from the drag start each move, like the prototype:
            // dragging up (smaller y) increases the value, ~7px per step.
            final step = ((_startY - d.globalPosition.dy) / 7).round();
            widget.onChanged(widget.wrap(_startValue, step));
          },
          child: SizedBox(
            width: 96,
            child: Text(
              widget.format(widget.value),
              textAlign: TextAlign.center,
              style: RiseText.mono(size: 66, weight: FontWeight.w500, color: RiseColors.text),
            ),
          ),
        ),
        _chevron(false, widget.onDecrement),
      ],
    );
  }

  Widget _chevron(bool up, VoidCallback onTap) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 44,
          height: 34,
          margin: const EdgeInsets.symmetric(vertical: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: RiseColors.surface2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: RiseColors.border),
          ),
          child: Icon(up ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              size: 18, color: RiseColors.textDim),
        ),
      );
}

class _AmPmButton extends StatelessWidget {
  const _AmPmButton({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? RiseColors.primary : RiseColors.surface2,
            borderRadius: BorderRadius.circular(11),
            border: selected ? null : Border.all(color: RiseColors.border),
          ),
          child: Text(label,
              style: RiseText.mono(
                  size: 15,
                  weight: FontWeight.w700,
                  color: selected ? RiseColors.primaryText : RiseColors.textDim)),
        ),
      );
}
