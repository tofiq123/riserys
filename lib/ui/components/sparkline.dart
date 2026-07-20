import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// A tiny line chart of [values], scaled to [min]..[max] on the vertical axis
/// and stretched to fill the available width. Pure and stateless — safe to pump
/// in tests. With a single value it draws a flat baseline dot; empty draws
/// nothing.
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.values,
    this.min = 0,
    this.max = 100,
    this.height = 44,
    this.color = RiseColors.text,
    this.strokeWidth = 2,
  });

  final List<double> values;
  final double min;
  final double max;
  final double height;
  final Color color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparklinePainter(
          values: values,
          min: min,
          max: max,
          color: color,
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.values,
    required this.min,
    required this.max,
    required this.color,
    required this.strokeWidth,
  });

  final List<double> values;
  final double min;
  final double max;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final span = (max - min).abs() < 1e-9 ? 1.0 : (max - min);
    final pad = strokeWidth + 1;
    final usableH = size.height - pad * 2;

    Offset pointAt(int i) {
      final x = values.length == 1
          ? size.width / 2
          : size.width * i / (values.length - 1);
      final norm = ((values[i] - min) / span).clamp(0.0, 1.0);
      final y = pad + (1 - norm) * usableH;
      return Offset(x, y);
    }

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (values.length == 1) {
      canvas.drawCircle(pointAt(0), strokeWidth, Paint()..color = color);
      return;
    }

    final path = Path()..moveTo(pointAt(0).dx, pointAt(0).dy);
    for (var i = 1; i < values.length; i++) {
      final p = pointAt(i);
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, paint);
    // Emphasise the latest point.
    canvas.drawCircle(
        pointAt(values.length - 1), strokeWidth + 0.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.values != values ||
      old.min != min ||
      old.max != max ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}
