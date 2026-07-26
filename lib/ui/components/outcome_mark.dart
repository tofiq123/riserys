import 'package:flutter/widgets.dart';

import '../../domain/wake_rhythm.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// The ONE place a [RhythmOutcome] becomes a drawn mark.
///
/// **Shape carries the value; colour only repeats it.** Running the shipped
/// palette through a colour-vision check: on the light ground on-time
/// (`positive`) and slept-through (`danger`) are ~5 ΔE apart under deuteranopia,
/// and `waking` vs `positive` is worse still — both below the floor at which two
/// marks can be told apart by hue. So every outcome gets a distinct silhouette:
///
/// | outcome        | shape                        |
/// |----------------|------------------------------|
/// | on time        | filled                       |
/// | late           | hollow ring                  |
/// | slept through  | cross                        |
/// | rest day       | horizontal dash              |
/// | pending        | vertical bar                 |
/// | no alarm       | small baseline dot           |
/// | + freeze used  | a centre pip on top          |
///
/// Everything that draws an outcome — the rhythm chart, the consistency grid,
/// the Morning Line rail, the streak hero's week dots and the legend — goes
/// through [paintOutcomeMark], so the vocabulary cannot drift between surfaces.
/// The tokens are the app's existing ones on purpose: chart-only colours would
/// make the same fact look different in two places.
///
/// Small marks on the light ground fall under the 3:1 mark-contrast guideline,
/// so the relief is mandatory and shipped: a labelled legend is always present
/// and the chart carries a "Show as a list" view of the same data.
void paintOutcomeMark(
  Canvas canvas,
  Offset center,
  RhythmOutcome outcome, {
  required double radius,
  required Color surface,
  bool freeze = false,
  bool square = false,
  bool dimmed = false,
}) {
  final color = outcomeColor(outcome);
  final o = dimmed ? 0.45 : 1.0;

  Paint fill(Color c) => Paint()
    ..color = c.withValues(alpha: c.a * o)
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;
  Paint stroke(Color c, double w) => Paint()
    ..color = c.withValues(alpha: c.a * o)
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..isAntiAlias = true;

  RRect box(double inset) => RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: center,
            width: (radius - inset) * 2,
            height: (radius - inset) * 2),
        Radius.circular(radius * 0.42),
      );

  void plate() {
    // The grid's quiet backing, so an empty cell still reads as a day.
    if (square) canvas.drawRRect(box(0), fill(RiseColors.surface2));
  }

  switch (outcome) {
    case RhythmOutcome.onTime:
      if (square) {
        canvas.drawRRect(box(0), fill(color));
      } else {
        canvas.drawCircle(center, radius, fill(color));
      }

    case RhythmOutcome.late:
      // Filled with the surface first so a connecting line cannot show through
      // the middle of a ring and read as a filled mark.
      if (square) {
        canvas.drawRRect(box(1.1), fill(surface));
        canvas.drawRRect(box(1.1), stroke(color, 2.2));
      } else {
        canvas.drawCircle(center, radius - 1.1, fill(surface));
        canvas.drawCircle(center, radius - 1.1, stroke(color, 2.2));
      }

    case RhythmOutcome.sleptThrough:
      plate();
      final r = radius * (square ? 0.52 : 0.86);
      canvas.drawLine(center.translate(-r, -r), center.translate(r, r),
          stroke(color, 2.2));
      canvas.drawLine(center.translate(r, -r), center.translate(-r, r),
          stroke(color, 2.2));

    case RhythmOutcome.restDay:
      plate();
      final r = radius * (square ? 0.55 : 0.95);
      canvas.drawLine(
          center.translate(-r, 0), center.translate(r, 0), stroke(color, 2.1));

    case RhythmOutcome.pending:
      plate();
      final r = radius * (square ? 0.55 : 0.95);
      canvas.drawLine(
          center.translate(0, -r), center.translate(0, r), stroke(color, 2.3));

    case RhythmOutcome.noAlarm:
      if (square) {
        canvas.drawRRect(box(0), fill(RiseColors.surface2));
      } else {
        canvas.drawCircle(center, 1.7, fill(color));
      }
  }

  // A freeze is orthogonal: the morning stays honestly late or slept-through,
  // and this only says why the run survived it.
  if (freeze) {
    canvas.drawCircle(center, radius * 0.3, fill(RiseColors.asleep));
  }
}

/// The token each outcome wears. Late is deliberately the neutral ink, never
/// `danger`: a late morning is information, not a failure to be shamed.
Color outcomeColor(RhythmOutcome outcome) => switch (outcome) {
      RhythmOutcome.onTime => RiseColors.positive,
      RhythmOutcome.late => RiseColors.text,
      RhythmOutcome.sleptThrough => RiseColors.danger,
      RhythmOutcome.restDay => RiseColors.textFaint,
      RhythmOutcome.pending => RiseColors.waking,
      RhythmOutcome.noAlarm => RiseColors.border,
    };

/// The words beside each mark. Never a judgement.
String outcomeLabel(RhythmOutcome outcome) => switch (outcome) {
      RhythmOutcome.onTime => 'on time',
      RhythmOutcome.late => 'late',
      RhythmOutcome.sleptThrough => 'slept through',
      RhythmOutcome.restDay => 'rest day',
      RhythmOutcome.pending => 'not yet',
      RhythmOutcome.noAlarm => 'no alarm',
    };

/// One mark as a widget, for rails, legends and hero dots. Shares
/// [paintOutcomeMark] with the painters so the two can never diverge.
class OutcomeMark extends StatelessWidget {
  const OutcomeMark(
    this.outcome, {
    super.key,
    this.size = 11,
    this.freeze = false,
    this.square = false,
    this.surface,
  });

  final RhythmOutcome outcome;
  final double size;
  final bool freeze;
  final bool square;

  /// The ground behind the mark — a hollow ring is filled with it so nothing
  /// shows through. Defaults to the card surface.
  final Color? surface;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _MarkPainter(
          outcome: outcome,
          freeze: freeze,
          square: square,
          surface: surface ?? RiseColors.card,
        ),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter({
    required this.outcome,
    required this.freeze,
    required this.square,
    required this.surface,
  });

  final RhythmOutcome outcome;
  final bool freeze;
  final bool square;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    paintOutcomeMark(
      canvas,
      Offset(size.width / 2, size.height / 2),
      outcome,
      radius: size.shortestSide / 2,
      surface: surface,
      freeze: freeze,
      square: square,
    );
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.outcome != outcome ||
      old.freeze != freeze ||
      old.square != square ||
      old.surface != surface;
}

/// The legend that must accompany any surface drawing outcomes. Always present,
/// always labelled — identity is never left to colour alone.
class OutcomeLegend extends StatelessWidget {
  const OutcomeLegend({super.key, this.outcomes, this.square = false});

  /// Which entries to show. Defaults to the four that describe a settled
  /// morning; pass a narrower list when a surface genuinely cannot produce the
  /// others, so the legend never explains marks that aren't there.
  final List<RhythmOutcome>? outcomes;
  final bool square;

  static const _default = [
    RhythmOutcome.onTime,
    RhythmOutcome.late,
    RhythmOutcome.sleptThrough,
    RhythmOutcome.restDay,
  ];

  @override
  Widget build(BuildContext context) {
    final items = outcomes ?? _default;
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: [
        for (final o in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutcomeMark(o, size: 11, square: square),
              const SizedBox(width: 6),
              Text(outcomeLabel(o),
                  style: RiseText.caption.copyWith(fontSize: 11.5)),
            ],
          ),
      ],
    );
  }
}
