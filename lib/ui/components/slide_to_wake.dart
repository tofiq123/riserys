import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Draggable "slide to wake up" track. The knob follows the drag; crossing 97%
/// of the travel fires [onWake] once. A shorter drag snaps the knob back.
class SlideToWake extends StatefulWidget {
  const SlideToWake({super.key, required this.onWake, this.label = 'Slide to wake up'});

  final VoidCallback onWake;
  final String label;

  @override
  State<SlideToWake> createState() => _SlideToWakeState();
}

class _SlideToWakeState extends State<SlideToWake> {
  static const double _trackHeight = 64;
  static const double _knob = 56;

  double _fraction = 0; // 0..1 of the available travel
  bool _fired = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final travel = (constraints.maxWidth - _knob).clamp(1.0, double.infinity);
        return GestureDetector(
          onHorizontalDragUpdate: (d) {
            if (_fired) return;
            setState(() => _fraction = (_fraction + d.delta.dx / travel).clamp(0.0, 1.0));
            if (_fraction >= 0.97) {
              _fired = true;
              widget.onWake();
            }
          },
          onHorizontalDragEnd: (_) {
            if (!_fired && _fraction < 0.97) setState(() => _fraction = 0);
          },
          child: Container(
            height: _trackHeight,
            decoration: BoxDecoration(
              color: RiseColors.card,
              borderRadius: BorderRadius.circular(RiseRadii.pill),
              border: Border.all(color: RiseColors.border),
            ),
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: _knob + _fraction * travel,
                  child: Container(
                    decoration: BoxDecoration(
                      color: RiseColors.accentSoft,
                      borderRadius: BorderRadius.circular(RiseRadii.pill),
                    ),
                  ),
                ),
                Center(
                  child: Text(widget.label,
                      style: RiseText.body.copyWith(
                          fontWeight: FontWeight.w600, color: RiseColors.textFaint)),
                ),
                Positioned(
                  left: 4 + _fraction * travel,
                  top: 4,
                  child: Container(
                    width: _knob,
                    height: _knob,
                    decoration: BoxDecoration(
                      color: RiseColors.primary,
                      shape: BoxShape.circle,
                      boxShadow: RiseShadows.primary,
                    ),
                    child: Icon(Icons.arrow_forward, color: RiseColors.primaryText, size: 24),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
