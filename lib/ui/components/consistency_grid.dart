import 'package:flutter/material.dart';

import '../../domain/wake_rhythm.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'outcome_mark.dart';

/// Five weeks of mornings as a real calendar: Monday-first columns with weekday
/// headers, one cell per day, today ringed.
///
/// The old version was an undated 30-cell `Wrap` — the cells did not line up
/// under a weekday, so "I always miss Mondays" was invisible in it. Feed it
/// [buildRhythmWeeks], which always starts on a Monday, so the grid never needs
/// leading blanks and the last row is simply short.
class ConsistencyGrid extends StatelessWidget {
  const ConsistencyGrid({super.key, required this.days, this.showTally = true});

  final List<RhythmDay> days;
  final bool showTally;

  static const _gap = 6.0;
  static const _headerHeight = 16.0;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) {
      return Text('Nothing logged in these weeks yet.', style: RiseText.caption);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final cell = (width - _gap * 6) / 7;
            final rows = (days.length / 7).ceil();
            final height =
                _headerHeight + rows * cell + (rows - 1) * _gap;
            return RepaintBoundary(
              child: CustomPaint(
                size: Size(width, height),
                painter: _GridPainter(
                  days: days,
                  gap: _gap,
                  headerHeight: _headerHeight,
                  card: RiseColors.card,
                  faint: RiseColors.textFaint,
                  ink: RiseColors.text,
                ),
              ),
            );
          },
        ),
        if (showTally) ...[
          const SizedBox(height: 12),
          OutcomeLegend(outcomes: _present, square: true),
          const SizedBox(height: 10),
          Text(rhythmTallyLine(days), style: RiseText.caption),
        ],
      ],
    );
  }

  List<RhythmOutcome> get _present {
    final seen = <RhythmOutcome>{for (final d in days) d.outcome};
    return [
      for (final o in RhythmOutcome.values)
        if (seen.contains(o) && o != RhythmOutcome.noAlarm) o
    ];
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter({
    required this.days,
    required this.gap,
    required this.headerHeight,
    required this.card,
    required this.faint,
    required this.ink,
  });

  final List<RhythmDay> days;
  final double gap, headerHeight;
  final Color card, faint, ink;

  static const _initials = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  void paint(Canvas canvas, Size size) {
    final cell = (size.width - gap * 6) / 7;
    if (cell <= 0) return;

    for (var col = 0; col < 7; col++) {
      _text(canvas, _initials[col],
          Offset(col * (cell + gap) + cell / 2, 0), faint, 9.5);
    }

    for (var i = 0; i < days.length; i++) {
      final col = i % 7, row = i ~/ 7;
      final centre = Offset(
        col * (cell + gap) + cell / 2,
        headerHeight + row * (cell + gap) + cell / 2,
      );
      paintOutcomeMark(
        canvas,
        centre,
        days[i].outcome,
        radius: cell / 2,
        surface: card,
        freeze: days[i].freezeAbsorbed,
        square: true,
      );
      // Today wears a ring just outside its cell, so "where am I" needs no
      // legend entry and never changes the day's own mark.
      if (i == days.length - 1) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: centre, width: cell + 5, height: cell + 5),
            Radius.circular(cell * 0.42 + 2),
          ),
          Paint()
            ..color = ink.withValues(alpha: 0.45)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4,
        );
      }
    }
  }

  /// Draws [value] centred horizontally on [at], with [at] as its top edge.
  void _text(
      Canvas canvas, String value, Offset at, Color color, double size) {
    final tp = TextPainter(
      text: TextSpan(
          text: value,
          style:
              RiseText.mono(size: size, weight: FontWeight.w500, color: color)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(at.dx - tp.width / 2, at.dy));
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      !identical(old.days, days) || old.card != card || old.ink != ink;
}
