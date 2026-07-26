import 'package:flutter/material.dart';

import '../../domain/clock_format.dart';
import '../../domain/period_stats.dart';
import '../../domain/streak.dart';
import '../../domain/wake_rhythm.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'hero_card.dart';
import 'outcome_mark.dart';
import 'rise_motion.dart';

/// The one block that answers "how am I doing?" without a scroll.
///
/// The four figures that used to live in four separate sections hundreds of
/// pixels apart now sit on one row, because comparison is the whole point of
/// having four of them. The period control sits directly above them, so it is
/// obvious which window they describe.
class StatSummary extends StatelessWidget {
  const StatSummary({
    super.key,
    required this.streak,
    required this.week,
    required this.stats,
    required this.consistency,
    required this.period,
    required this.periodsLocked,
    required this.onPeriod,
    this.use24h = true,
    this.line,
  });

  final StreakStats streak;

  /// The last seven mornings, for the outcome marks beside the run.
  final List<RhythmDay> week;

  /// Aggregates over the selected [period].
  final PeriodStats stats;
  final int? consistency;

  final StatsPeriod period;

  /// Month and Year are premium; locked periods show the glyph and route to the
  /// paywall instead of silently doing nothing.
  final bool periodsLocked;
  final ValueChanged<StatsPeriod> onPeriod;

  final bool use24h;

  /// One plain sentence under the run. Null falls back to a derived one.
  final String? line;

  String get _line {
    if (line != null) return line!;
    final settled = settledDays(week);
    if (settled.isEmpty) return 'No mornings logged this week yet.';
    final onTime =
        settled.where((d) => d.outcome == RhythmOutcome.onTime).length;
    final base = 'On time $onTime of ${settled.length} this week.';
    final froze = week.where((d) => d.freezeAbsorbed).length;
    if (froze == 0) return base;
    return '$base A freeze covered ${froze == 1 ? 'one' : '$froze'}.';
  }

  @override
  Widget build(BuildContext context) {
    final onp = RiseColors.primaryText;
    return HeroCard(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Opacity(
                      opacity: 0.62,
                      child: Text('CURRENT RUN',
                          style:
                              RiseText.sectionLabel.copyWith(color: onp)),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(
                          child: RiseCountUp(
                            value: streak.current,
                            style: RiseText.mono(
                                size: 50,
                                weight: FontWeight.w600,
                                color: onp,
                                letterSpacing: -1.8),
                          ),
                        ),
                        const SizedBox(width: 9),
                        Flexible(
                          child: Opacity(
                            opacity: 0.78,
                            child: Text(
                                streak.current == 1 ? 'day' : 'days',
                                style: RiseText.body
                                    .copyWith(color: onp, fontSize: 15),
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.fade),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (week.isNotEmpty) _WeekMarks(week: week, ink: onp),
            ],
          ),
          const SizedBox(height: 10),
          Opacity(
            opacity: 0.75,
            child: Text(_line, style: RiseText.caption.copyWith(color: onp)),
          ),
          const SizedBox(height: 16),
          _Periods(
            period: period,
            locked: periodsLocked,
            onChanged: onPeriod,
            ink: onp,
          ),
          const SizedBox(height: 14),
          Container(height: 1, color: onp.withValues(alpha: 0.18)),
          const SizedBox(height: 16),
          _Figures(
            stats: stats,
            consistency: consistency,
            use24h: use24h,
            ink: onp,
          ),
        ],
      ),
    );
  }
}

/// The last seven mornings in the shared mark vocabulary — the same shapes the
/// chart and the grid use, so the hero teaches the legend before you meet it.
class _WeekMarks extends StatelessWidget {
  const _WeekMarks({required this.week, required this.ink});

  final List<RhythmDay> week;
  final Color ink;

  static const double _mark = 9, _gap = 5;

  @override
  Widget build(BuildContext context) {
    final last = week.length > 7 ? week.sublist(week.length - 7) : week;
    // The marks decide the block's width — never the caption. A long caption or
    // a large text scale would otherwise squeeze the run beside it off screen.
    final width = last.length * (_mark + _gap);
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final d in last)
                Padding(
                  padding: const EdgeInsets.only(left: _gap),
                  child: OutcomeMark(d.outcome,
                      size: _mark,
                      freeze: d.freezeAbsorbed,
                      surface: RiseColors.primary,
                      ink: ink),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Opacity(
            opacity: 0.6,
            child: Text('last 7 mornings',
                style: RiseText.caption.copyWith(fontSize: 10.5, color: ink),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.fade,
                textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

class _Periods extends StatelessWidget {
  const _Periods({
    required this.period,
    required this.locked,
    required this.onChanged,
    required this.ink,
  });

  final StatsPeriod period;
  final bool locked;
  final ValueChanged<StatsPeriod> onChanged;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final p in StatsPeriod.values)
          Padding(
            padding: const EdgeInsets.only(right: 18),
            child: Semantics(
              button: true,
              selected: p == period,
              child: GestureDetector(
                key: Key('summary-period-${p.name}'),
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(p),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 30),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                          color: p == period ? ink : Colors.transparent,
                          width: 1.5),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Opacity(
                        opacity: p == period ? 1 : 0.5,
                        child: Text(periodLabel(p),
                            style: RiseText.body.copyWith(
                                color: ink,
                                fontSize: 12.5,
                                fontWeight: p == period
                                    ? FontWeight.w600
                                    : FontWeight.w400)),
                      ),
                      if (locked && p != StatsPeriod.week) ...[
                        const SizedBox(width: 5),
                        Opacity(
                          opacity: 0.5,
                          child: Icon(Icons.lock_outline, size: 11, color: ink),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Four figures on one row — and a 2×2 on a narrow phone rather than four
/// truncated labels.
class _Figures extends StatelessWidget {
  const _Figures({
    required this.stats,
    required this.consistency,
    required this.use24h,
    required this.ink,
  });

  final PeriodStats stats;
  final int? consistency;
  final bool use24h;
  final Color ink;

  /// Below this per column the labels would start truncating, so the row
  /// becomes a 2×2 instead. "consistency" is the widest label and sets it; four
  /// of these fit the 291pt inner width of a 375pt phone's hero.
  static const double minColumn = 70;

  @override
  Widget build(BuildContext context) {
    final rate = stats.onTimeRate;
    final avg = stats.avgWakeMinute;
    final figures = <({String label, String value, String sub})>[
      (
        label: 'on time',
        value: rate == null ? '—' : '${(rate * 100).round()}%',
        sub: rate == null ? 'no wakes yet' : '${stats.onTimeCount}/${stats.count}'
      ),
      (
        label: 'avg wake',
        value:
            avg == null ? '—' : formatClock(avg ~/ 60, avg % 60, use24h: use24h),
        sub: 'typical'
      ),
      (
        label: 'best run',
        value: '${stats.bestStreak}',
        sub: stats.bestStreak == 1 ? 'day' : 'days'
      ),
      (
        label: 'consistency',
        value: consistency == null ? '—' : '$consistency',
        sub: consistency == null ? 'building' : 'out of 100'
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final perRow = constraints.maxWidth >= minColumn * 4 ? 4 : 2;
        final width = constraints.maxWidth / perRow;
        return Wrap(
          runSpacing: 16,
          children: [
            for (final f in figures)
              SizedBox(
                  width: width,
                  child: _figure(f.label, f.value, f.sub)),
          ],
        );
      },
    );
  }

  Widget _figure(String label, String value, String sub) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: RiseText.mono(
                  size: 20,
                  weight: FontWeight.w600,
                  color: ink,
                  letterSpacing: -0.4),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Opacity(
            opacity: 0.72,
            child: Text(label,
                style: RiseText.caption.copyWith(color: ink, fontSize: 11.5),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(height: 2),
          Opacity(
            opacity: 0.45,
            child: Text(sub,
                style: RiseText.mono(size: 10, color: ink),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      );
}
