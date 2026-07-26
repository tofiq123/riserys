import 'package:flutter/material.dart';

import '../../domain/clock_format.dart';
import '../../domain/wake_rhythm.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'outcome_mark.dart';
import 'rise_card.dart';

/// When you actually get up, against the window you had to do it in.
///
/// The y axis is clock time and the shaded band per day runs from the alarm's
/// first ring to the end of the on-time grace — so the band *is* the on-time
/// rule. A mark inside it is on time by construction, which means position and
/// shape can never tell different stories. The band steps when the alarm moves,
/// which shows weekend drift for free.
///
/// This replaces a chart of "minutes late", which could not answer the question
/// people actually have.
class WakeRhythmChart extends StatefulWidget {
  const WakeRhythmChart({
    super.key,
    required this.days,
    this.height = 168,
    this.showList = true,
    this.use24h = true,
    this.compact = false,
  });

  final List<RhythmDay> days;
  final double height;

  /// Offers the "Show as a list" view of the same data — the relief that keeps
  /// the chart readable when the marks themselves are too small to separate.
  final bool showList;
  final bool use24h;

  /// Drops the legend and the list toggle, for the smaller copy on a friend's
  /// page where the surrounding card already carries the explanation.
  final bool compact;

  @override
  State<WakeRhythmChart> createState() => _WakeRhythmChartState();
}

class _WakeRhythmChartState extends State<WakeRhythmChart> {
  bool _asList = false;

  /// Only the outcomes actually present, so the legend never explains a mark
  /// that isn't on screen.
  List<RhythmOutcome> get _present {
    final seen = <RhythmOutcome>{for (final d in widget.days) d.outcome};
    return [
      for (final o in RhythmOutcome.values)
        if (seen.contains(o) && o != RhythmOutcome.noAlarm) o
    ];
  }

  @override
  Widget build(BuildContext context) {
    final settled = settledDays(widget.days);
    if (settled.isEmpty) return const _NoMornings();

    if (_asList) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DayList(days: widget.days, use24h: widget.use24h),
          const SizedBox(height: 12),
          _toggle(),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RepaintBoundary(
          child: SizedBox(
            height: widget.height,
            width: double.infinity,
            child: CustomPaint(
              painter: _RhythmPainter(
                days: widget.days,
                range: rhythmRange(widget.days),
                use24h: widget.use24h,
                card: RiseColors.card,
                grid: RiseColors.divider,
                ink: RiseColors.text,
                faint: RiseColors.textFaint,
                band: RiseColors.positive,
              ),
            ),
          ),
        ),
        if (!widget.compact) ...[
          const SizedBox(height: 12),
          OutcomeLegend(outcomes: _present),
          if (widget.showList) ...[
            const SizedBox(height: 12),
            _toggle(),
          ],
        ],
      ],
    );
  }

  Widget _toggle() => Semantics(
        button: true,
        child: GestureDetector(
          key: const Key('rhythm-list-toggle'),
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _asList = !_asList),
          child: Container(
            alignment: Alignment.center,
            constraints: const BoxConstraints(minHeight: 38),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(RiseRadii.sm),
              border: Border.all(color: RiseColors.border),
            ),
            child: Text(_asList ? 'Show as a chart' : 'Show as a list',
                style: RiseText.body.copyWith(
                    fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ),
      );
}

/// The same data as exact times — the chart's accessible twin, not a fallback.
class _DayList extends StatelessWidget {
  const _DayList({required this.days, required this.use24h});

  final List<RhythmDay> days;
  final bool use24h;

  static const _weekday = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  String _time(int? minute) => minute == null
      ? '—'
      : formatClock((minute ~/ 60) % 24, minute % 60, use24h: use24h);

  @override
  Widget build(BuildContext context) {
    final rows = [
      for (final d in days.reversed)
        if (d.outcome != RhythmOutcome.noAlarm) d
    ];
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 9),
            child: Row(
              children: [
                OutcomeMark(rows[i].outcome,
                    size: 11, freeze: rows[i].freezeAbsorbed),
                const SizedBox(width: 10),
                SizedBox(
                  width: 62,
                  child: Text(
                      '${_weekday[rows[i].day.weekday - 1]} '
                      '${rows[i].day.day}',
                      style: RiseText.caption),
                ),
                Text(_time(rows[i].wokeMinute),
                    style: RiseText.mono(size: 13, weight: FontWeight.w600)),
                const Spacer(),
                Text(outcomeLabel(rows[i].outcome),
                    style: RiseText.caption.copyWith(fontSize: 11.5)),
              ],
            ),
          ),
      ],
    );
  }
}

/// Before there is anything to plot: say what appears and when, never an empty
/// axis pretending to be a chart.
class _NoMornings extends StatelessWidget {
  const _NoMornings();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.schedule, size: 26, color: RiseColors.textFaint),
          const SizedBox(height: 10),
          Text('No mornings to chart yet',
              style: RiseText.body.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
              'Your first alarm starts the picture — one mark per morning, '
              'against the window you had to get up in.',
              style: RiseText.caption),
        ],
      ),
    );
  }
}

class _RhythmPainter extends CustomPainter {
  const _RhythmPainter({
    required this.days,
    required this.range,
    required this.use24h,
    required this.card,
    required this.grid,
    required this.ink,
    required this.faint,
    required this.band,
  });

  final List<RhythmDay> days;
  final ({int lo, int hi}) range;
  final bool use24h;
  final Color card, grid, ink, faint, band;

  static const _padR = 6.0, _padT = 10.0, _padB = 18.0;

  /// Wide enough for the widest axis label the user's clock format produces —
  /// "07:05" is narrow, "7:05 AM" is not.
  double get _padL => use24h ? 42 : 56;

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty) return;
    final iw = size.width - _padL - _padR;
    final ih = size.height - _padT - _padB;
    if (iw <= 0 || ih <= 0) return;

    final span = (range.hi - range.lo).clamp(1, 24 * 60);
    double y(num m) => _padT + ((m - range.lo) / span) * ih;
    double x(int i) => _padL + ((i + 0.5) / days.length) * iw;

    // ── gridlines, on whole hours where they fit, else half hours ───────────
    final stepMin = span > 240 ? 60 : (span > 120 ? 30 : 15);
    final firstLine = ((range.lo + stepMin - 1) ~/ stepMin) * stepMin;
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var m = firstLine; m <= range.hi; m += stepMin) {
      final gy = y(m);
      canvas.drawLine(Offset(_padL, gy), Offset(size.width - _padR, gy),
          gridPaint);
      _text(
        canvas,
        formatClock((m ~/ 60) % 24, m % 60, use24h: use24h),
        Offset(_padL - 6, gy),
        color: faint,
        size: 9,
        anchorRight: true,
      );
    }

    // ── the on-time band, stepping with each day's alarm ────────────────────
    final bandPaint = Paint()..color = band.withValues(alpha: 0.13);
    final edgePaint = Paint()
      ..color = band.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    final slot = iw / days.length;
    for (var i = 0; i < days.length; i++) {
      final ring = days[i].ringMinute, end = days[i].graceEndMinute;
      if (ring == null || end == null) continue;
      final left = _padL + i * slot;
      final top = y(end), bottom = y(ring);
      canvas.drawRect(
          Rect.fromLTRB(left, top, left + slot, bottom), bandPaint);
      // The alarm itself: the band's lower edge.
      canvas.drawLine(
          Offset(left, bottom), Offset(left + slot, bottom), edgePaint);
    }

    // ── the connecting hairline, only between consecutive plotted marks ─────
    final linePaint = Paint()
      ..color = ink.withValues(alpha: 0.16)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    Offset? prev;
    for (var i = 0; i < days.length; i++) {
      final woke = days[i].wokeMinute;
      if (woke == null) {
        prev = null;
        continue;
      }
      final p = Offset(x(i), y(woke));
      if (prev != null) canvas.drawLine(prev, p, linePaint);
      prev = p;
    }

    // ── the marks ──────────────────────────────────────────────────────────
    for (var i = 0; i < days.length; i++) {
      final d = days[i];
      final at = d.wokeMinute ?? d.ringMinute;
      if (at == null && d.outcome != RhythmOutcome.noAlarm) continue;
      final cy = at == null ? _padT + ih : y(at);
      paintOutcomeMark(
        canvas,
        Offset(x(i), cy.clamp(_padT, _padT + ih)),
        d.outcome,
        radius: 4.6,
        surface: card,
        freeze: d.freezeAbsorbed,
      );
    }

    // ── labels: the latest morning, and the worst one, and nothing else ────
    final latest = _lastPlotted();
    final worst = _worstPlotted();
    for (final i in {latest, worst}) {
      if (i == null) continue;
      final woke = days[i].wokeMinute!;
      _text(
        canvas,
        formatClock((woke ~/ 60) % 24, woke % 60, use24h: use24h),
        Offset(x(i), y(woke) - 20),
        color: ink,
        size: 9.5,
        centred: true,
      );
    }

    // ── weekday initials ───────────────────────────────────────────────────
    const initials = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    for (var i = 0; i < days.length; i++) {
      _text(
        canvas,
        initials[days[i].day.weekday - 1],
        Offset(x(i), size.height - _padB + 3),
        color: faint,
        size: 8.5,
        centred: true,
      );
    }
  }

  int? _lastPlotted() {
    for (var i = days.length - 1; i >= 0; i--) {
      if (days[i].wokeMinute != null) return i;
    }
    return null;
  }

  int? _worstPlotted() {
    int? best;
    var worstLate = 0;
    for (var i = 0; i < days.length; i++) {
      final late = days[i].lateBy;
      if (late != null && late > worstLate) {
        worstLate = late;
        best = i;
      }
    }
    return best;
  }

  /// Draws [value] with one of two anchors: [centred] puts [at] at the top
  /// centre of the text (marks and weekday initials), [anchorRight] puts it at
  /// the middle of the right edge (axis labels). Exactly one applies.
  void _text(
    Canvas canvas,
    String value,
    Offset at, {
    required Color color,
    required double size,
    bool centred = false,
    bool anchorRight = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
          text: value,
          style:
              RiseText.mono(size: size, weight: FontWeight.w500, color: color)),
      textDirection: TextDirection.ltr,
    )..layout();
    final origin = anchorRight
        ? Offset(at.dx - tp.width, at.dy - tp.height / 2)
        : centred
            ? Offset(at.dx - tp.width / 2, at.dy)
            : at;
    tp.paint(canvas, origin);
  }

  @override
  bool shouldRepaint(_RhythmPainter old) =>
      !identical(old.days, days) ||
      old.range != range ||
      old.use24h != use24h ||
      old.card != card ||
      old.ink != ink;
}
