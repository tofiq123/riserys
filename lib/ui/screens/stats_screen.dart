import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/excused_days_repository.dart';
import '../../domain/achievements.dart';
import '../../domain/alertness_trend.dart';
import '../../domain/consistency.dart';
import '../../domain/crew_standing.dart';
import '../../domain/rise_settings.dart';
import '../../domain/streak.dart';
import '../../domain/wake_event.dart';
import '../../domain/wake_insights.dart';
import '../components/rise_card.dart';
import '../components/section_label.dart';
import '../components/shareable_stats_card.dart';
import '../components/sparkline.dart';
import '../share/stats_share.dart';
import '../state/auth_providers.dart';
import '../state/leaderboard_providers.dart';
import '../state/settings_providers.dart';
import '../state/wake_providers.dart';
import '../theme/avatar_color.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

DateTime _todayLocal(DateTime now) {
  final l = now.toLocal();
  return DateTime(l.year, l.month, l.day);
}

/// The representative wake for one local day.
class DayWake {
  const DayWake(this.day,
      {this.deltaMinutes, required this.onTime, required this.hasEvent});

  final DateTime day;

  /// dismissed − scheduled, in minutes; null when the day had no dismissal.
  final int? deltaMinutes;
  final bool onTime;
  final bool hasEvent;
}

/// The last 7 local days (oldest first), each with its representative wake:
/// the on-time event if any, else the latest event.
List<DayWake> weekWakes(List<WakeEvent> events, DateTime now) {
  final today = _todayLocal(now);
  final byDay = <DateTime, WakeEvent>{};
  for (final e in events) {
    final d = e.localDay;
    final cur = byDay[d];
    final better = cur == null ||
        (e.onTime && !cur.onTime) ||
        (e.onTime == cur.onTime && e.firstRingAt.isAfter(cur.firstRingAt));
    if (better) byDay[d] = e;
  }
  return [
    for (var i = 6; i >= 0; i--)
      () {
        final day = today.subtract(Duration(days: i));
        final e = byDay[day];
        if (e == null) return DayWake(day, onTime: false, hasEvent: false);
        final delta = e.dismissedAt?.difference(e.scheduledAt).inMinutes;
        return DayWake(day,
            deltaMinutes: delta, onTime: e.onTime, hasEvent: true);
      }(),
  ];
}

/// "On time X of Y this week", or a no-data line.
String consistencyLine(List<WakeEvent> events, DateTime now) {
  final wakes = weekWakes(events, now);
  final rang = wakes.where((w) => w.hasEvent).length;
  final onTime = wakes.where((w) => w.onTime).length;
  if (rang == 0) return 'No wake-ups yet this week.';
  return 'On time $onTime of $rang this week.';
}

/// The mean of the non-null alertness scores across [events], rounded to the
/// nearest integer; null when no event carries a score.
int? averageAlertness(List<WakeEvent> events) {
  final scores = [
    for (final e in events)
      if (e.alertnessScore != null) e.alertnessScore!
  ];
  if (scores.isEmpty) return null;
  final sum = scores.fold<int>(0, (a, b) => a + b);
  return (sum / scores.length).round();
}

/// A neutral, non-judgemental descriptor for an alertness [score]. Purely
/// informational — never a medical, diagnostic, or "abnormal" label.
String alertnessBand(int score) {
  if (score >= 80) return 'sharp';
  if (score >= 50) return 'steady';
  return 'groggy';
}

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key, this.shareRunner});

  /// Test seam: overrides the capture-and-share step so the failure UI can be
  /// exercised headlessly. Null in production, where the real
  /// [captureAndShare] rasterises the offscreen card and opens the share sheet.
  final Future<void> Function(GlobalKey boundaryKey)? shareRunner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streak = ref.watch(streakProvider);
    final events = ref.watch(wakeEventsProvider).value ?? const <WakeEvent>[];
    final settings = ref.watch(currentSettingsProvider);
    final now = DateTime.now();

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            RiseSpacing.screen, 8, RiseSpacing.screen, 40),
        children: [
          Text('Stats', style: RiseText.display),
          const SizedBox(height: 16),
          if (events.isEmpty)
            _empty()
          else ...[
            _streakCard(streak),
            const SizedBox(height: 12),
            const _RoughNightCard(),
            const SizedBox(height: 12),
            _ShareCard(shareRunner: shareRunner),
            const SizedBox(height: 24),
            const SectionLabel('Last 30 days'),
            const SizedBox(height: 12),
            _calendar(streak.byDay, now),
            const SizedBox(height: 24),
            const SectionLabel('This week'),
            const SizedBox(height: 6),
            Text(consistencyLine(events, now), style: RiseText.caption),
            const SizedBox(height: 14),
            _weekChart(weekWakes(events, now)),
            const SizedBox(height: 24),
            const SectionLabel('Consistency'),
            const SizedBox(height: 12),
            _consistencyCard(events),
            const SizedBox(height: 24),
            const _AchievementsSection(),
            ..._insightsWidgets(events, settings),
            const SizedBox(height: 24),
            const SectionLabel('Alertness'),
            const SizedBox(height: 12),
            _alertnessCard(events),
            ..._alertnessTrendWidgets(events),
          ],
          const SizedBox(height: 24),
          const _LeaderboardSection(),
        ],
      ),
    );
  }

  Widget _empty() => RiseCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
          child: Column(
            children: [
              const Icon(Icons.local_fire_department,
                  size: 40, color: RiseColors.textFaint),
              const SizedBox(height: 12),
              Text('No wake data yet',
                  style: RiseText.body.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Set an alarm and wake up on time — your streak grows from here.',
                  textAlign: TextAlign.center, style: RiseText.caption),
            ],
          ),
        ),
      );

  Widget _streakCard(StreakStats s) => RiseCard(
        padding: const EdgeInsets.all(RiseSpacing.screen),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Icon(Icons.local_fire_department,
                      color: RiseColors.waking, size: 30),
                ),
                const SizedBox(width: 8),
                Text('${s.current}',
                    style: RiseText.mono(size: 52, weight: FontWeight.w600)),
                const SizedBox(width: 8),
                Text(s.current == 1 ? 'day' : 'days',
                    style: RiseText.body.copyWith(color: RiseColors.textDim)),
              ],
            ),
            const SizedBox(height: 4),
            Text('current streak', style: RiseText.caption),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _miniStat('Best', '${s.best}'),
                Container(width: 1, height: 32, color: RiseColors.divider),
                _miniStat('Freezes', '${s.freezesRemaining}'),
              ],
            ),
          ],
        ),
      );

  Widget _miniStat(String label, String value) => Column(
        children: [
          Text(value, style: RiseText.mono(size: 22, weight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(label, style: RiseText.caption),
        ],
      );

  /// Honest, plain-language observations from the wake log — shown only once
  /// there's enough data to be meaningful. Never diagnostic or judgemental.
  /// Returns an empty list (and renders nothing) below that threshold.
  List<Widget> _insightsWidgets(List<WakeEvent> events, RiseSettings settings) {
    final insights = buildWakeInsights(events,
        targetWakeHour: settings.targetWakeHour,
        targetWakeMinute: settings.targetWakeMinute);
    if (insights.isEmpty) return const [];
    return [
      const SizedBox(height: 24),
      const SectionLabel('Your patterns'),
      const SizedBox(height: 6),
      Text('A few honest observations — not judgements.',
          style: RiseText.caption),
      const SizedBox(height: 12),
      for (final insight in insights) ...[
        _insightCard(insight),
        const SizedBox(height: 10),
      ],
    ];
  }

  Widget _insightCard(WakeInsight insight) => RiseCard(
        radius: RiseRadii.base,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_insightIcon(insight.kind),
                size: 20, color: RiseColors.textDim),
            const SizedBox(width: 12),
            Expanded(child: Text(insight.text, style: RiseText.body)),
          ],
        ),
      );

  IconData _insightIcon(WakeInsightKind kind) => switch (kind) {
        WakeInsightKind.onTime => Icons.check_circle_outline,
        WakeInsightKind.goal => Icons.wb_sunny_outlined,
        WakeInsightKind.weekdayWeekend => Icons.calendar_today_outlined,
        WakeInsightKind.consistentDay => Icons.event_available_outlined,
      };

  Widget _calendar(Map<DateTime, DayOutcome> byDay, DateTime now) {
    final today = _todayLocal(now);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var i = 29; i >= 0; i--)
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: _cellColor(byDay[today.subtract(Duration(days: i))]),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: RiseColors.border),
            ),
          ),
      ],
    );
  }

  Color _cellColor(DayOutcome? o) => switch (o) {
        DayOutcome.success => RiseColors.positive,
        DayOutcome.miss => RiseColors.danger,
        DayOutcome.pending => RiseColors.waking,
        DayOutcome.neutral || null => RiseColors.surface2,
      };

  Widget _weekChart(List<DayWake> wakes) {
    const maxMin = 30.0;
    const maxH = 64.0;
    return SizedBox(
      height: 100,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final w in wakes)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    width: 18,
                    height: w.deltaMinutes == null
                        ? 4
                        : 6 +
                            (w.deltaMinutes!.clamp(0, maxMin) / maxMin) * maxH,
                    decoration: BoxDecoration(
                      color: w.hasEvent
                          ? (w.onTime ? RiseColors.positive : RiseColors.danger)
                          : RiseColors.border,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(_weekdayLetter(w.day),
                      style: RiseText.caption.copyWith(fontSize: 10)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _weekdayLetter(DateTime day) {
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S']; // Mon..Sun
    return letters[(day.weekday - 1) % 7];
  }

  /// Reaction-speed alertness: latest score, average, and a small recent trend.
  /// The score is honest, non-diagnostic framing of raw PVT performance — never
  /// a medical or sleep-stage claim. Shows a helper state until a PVT mission
  /// has produced at least one score.
  Widget _alertnessCard(List<WakeEvent> events) {
    final scored = [
      for (final e in events)
        if (e.alertnessScore != null) e
    ]..sort((a, b) => a.firstRingAt.compareTo(b.firstRingAt));

    if (scored.isEmpty) {
      return RiseCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 8),
          child: Column(
            children: [
              const Icon(Icons.bolt_outlined,
                  size: 34, color: RiseColors.textFaint),
              const SizedBox(height: 10),
              Text('No alertness scores yet',
                  style: RiseText.body.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                  'Add an "Alertness (PVT)" mission to an alarm to measure your '
                  'reaction speed at wake-up.',
                  textAlign: TextAlign.center,
                  style: RiseText.caption),
            ],
          ),
        ),
      );
    }

    final latest = scored.last.alertnessScore!;
    final avg = averageAlertness(scored)!;
    final trend =
        scored.length > 7 ? scored.sublist(scored.length - 7) : scored;

    return RiseCard(
      padding: const EdgeInsets.all(RiseSpacing.screen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('$latest',
                  style: RiseText.mono(size: 44, weight: FontWeight.w600)),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _bandChip(latest),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$avg',
                      style: RiseText.mono(size: 22, weight: FontWeight.w600)),
                  Text('avg', style: RiseText.caption.copyWith(fontSize: 10)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text('latest score', style: RiseText.caption),
          const SizedBox(height: 12),
          Text(
              'Your reaction speed at wake-up — sharper is more awake. '
              'Not a medical measure.',
              style: RiseText.caption),
          const SizedBox(height: 16),
          _alertnessTrend(trend),
        ],
      ),
    );
  }

  /// Wake-time regularity as a single 0–100 figure. Shows a gentle helper until
  /// there are enough completed wake-ups to be meaningful.
  Widget _consistencyCard(List<WakeEvent> events) {
    final score = consistencyScore(events);
    if (score == null) {
      return RiseCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
          child: Column(
            children: [
              const Icon(Icons.insights_outlined,
                  size: 32, color: RiseColors.textFaint),
              const SizedBox(height: 10),
              Text('Building your consistency score',
                  style: RiseText.body.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                  'A few more wake-ups and we\'ll show how steady your wake '
                  'time is.',
                  textAlign: TextAlign.center,
                  style: RiseText.caption),
            ],
          ),
        ),
      );
    }
    final color = _consistencyColor(score);
    return RiseCard(
      padding: const EdgeInsets.all(RiseSpacing.screen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('$score',
                  style: RiseText.mono(size: 44, weight: FontWeight.w600)),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: RiseColors.surface2,
                    borderRadius: BorderRadius.circular(RiseRadii.pill),
                    border: Border.all(color: color),
                  ),
                  child: Text(consistencyBand(score),
                      style: RiseText.caption.copyWith(
                          color: color, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text('consistency', style: RiseText.caption),
          const SizedBox(height: 12),
          Text(
              'How steady your wake time is, day to day — higher is more '
              'regular. Not a judgement.',
              style: RiseText.caption),
        ],
      ),
    );
  }

  Color _consistencyColor(int score) {
    if (score >= 80) return RiseColors.positive;
    if (score >= 60) return RiseColors.waking;
    return RiseColors.asleep;
  }

  /// A longer-horizon alertness trend beyond the single Alertness card: a
  /// sparkline of the recent scores plus a plain-language direction. Hidden
  /// until there are enough scores for a trend to mean anything.
  List<Widget> _alertnessTrendWidgets(List<WakeEvent> events) {
    final scored = [
      for (final e in events)
        if (e.alertnessScore != null) e
    ]..sort((a, b) => a.firstRingAt.compareTo(b.firstRingAt));
    if (scored.length < kMinTrendScores) return const [];

    final recent =
        scored.length > 14 ? scored.sublist(scored.length - 14) : scored;
    final scores = [for (final e in recent) e.alertnessScore!];
    final trend = alertnessTrendOf(scores);

    return [
      const SizedBox(height: 24),
      const SectionLabel('Alertness trend'),
      const SizedBox(height: 6),
      Text(_trendLine(trend), style: RiseText.caption),
      const SizedBox(height: 12),
      RiseCard(
        padding: const EdgeInsets.all(RiseSpacing.screen),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_trendIcon(trend), size: 18, color: _trendColor(trend)),
                const SizedBox(width: 8),
                Text(_trendWord(trend),
                    style: RiseText.body.copyWith(
                        fontWeight: FontWeight.w700, color: _trendColor(trend))),
                const Spacer(),
                Text('last ${recent.length}',
                    style: RiseText.caption.copyWith(fontSize: 10)),
              ],
            ),
            const SizedBox(height: 14),
            Sparkline(
              values: [for (final s in scores) s.toDouble()],
              color: RiseColors.text,
              height: 48,
            ),
          ],
        ),
      ),
    ];
  }

  String _trendWord(AlertnessTrend t) => switch (t) {
        AlertnessTrend.rising => 'Trending up',
        AlertnessTrend.steady => 'Holding steady',
        AlertnessTrend.easing => 'Easing off',
        AlertnessTrend.insufficient => 'Not enough data',
      };

  String _trendLine(AlertnessTrend t) => switch (t) {
        AlertnessTrend.rising =>
          'Your wake-up reaction speed is picking up lately.',
        AlertnessTrend.steady => 'Your wake-up reaction speed is holding steady.',
        AlertnessTrend.easing =>
          'Your wake-up reaction speed has dipped a little lately.',
        AlertnessTrend.insufficient => 'A few more scores and a trend appears.',
      };

  IconData _trendIcon(AlertnessTrend t) => switch (t) {
        AlertnessTrend.rising => Icons.trending_up,
        AlertnessTrend.steady => Icons.trending_flat,
        AlertnessTrend.easing => Icons.trending_down,
        AlertnessTrend.insufficient => Icons.remove,
      };

  Color _trendColor(AlertnessTrend t) => switch (t) {
        AlertnessTrend.rising => RiseColors.positive,
        AlertnessTrend.steady => RiseColors.textDim,
        AlertnessTrend.easing => RiseColors.waking,
        AlertnessTrend.insufficient => RiseColors.textDim,
      };

  Widget _bandChip(int score) {
    final color = _bandColor(score);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: RiseColors.surface2,
        borderRadius: BorderRadius.circular(RiseRadii.pill),
        border: Border.all(color: color),
      ),
      child: Text(alertnessBand(score),
          style: RiseText.caption
              .copyWith(color: color, fontWeight: FontWeight.w700)),
    );
  }

  Widget _alertnessTrend(List<WakeEvent> scored) {
    const maxH = 48.0;
    return SizedBox(
      height: 56,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final e in scored)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Container(
                  height: 6 + (e.alertnessScore!.clamp(0, 100) / 100) * maxH,
                  decoration: BoxDecoration(
                    color: _bandColor(e.alertnessScore!),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Neutral, informational colours: green (sharp), amber (steady), indigo
  // (groggy). Deliberately NOT red/danger — a low score is information, never a
  // failure to be shamed.
  Color _bandColor(int score) {
    if (score >= 80) return RiseColors.positive;
    if (score >= 50) return RiseColors.waking;
    return RiseColors.asleep;
  }
}

/// A gentle, no-penalty affordance: mark a recent day as a "rough night" so it
/// does not break the streak. Deliberately warm and matter-of-fact — rest is
/// framed as legitimate, never as a failure. An excused day only protects the
/// streak; it never advances it, so there is nothing to game.
class _RoughNightCard extends ConsumerWidget {
  const _RoughNightCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Best-effort like streakProvider: an unavailable excused-days store must
    // never crash the Stats tab — fall back to an empty set.
    Set<DateTime> excused;
    try {
      excused = ref.watch(excusedDaysProvider).value ?? const <DateTime>{};
    } catch (_) {
      excused = const <DateTime>{};
    }
    final today = ExcusedDaysRepository.dayOf(DateTime.now());
    final yesterday = today.subtract(const Duration(days: 1));

    return GestureDetector(
      key: const Key('rough-night-card'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _showSheet(context, ref, today, yesterday, excused),
      child: RiseCard(
        child: Row(
          children: [
            const Icon(Icons.bedtime_outlined,
                color: RiseColors.asleep, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Rough night?',
                      style:
                          RiseText.body.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('Mark it — your streak stays safe. Rest counts too.',
                      style: RiseText.caption),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: RiseColors.textFaint, size: 20),
          ],
        ),
      ),
    );
  }

  void _showSheet(BuildContext context, WidgetRef ref, DateTime today,
      DateTime yesterday, Set<DateTime> excused) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: RiseColors.card,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(RiseSpacing.screen),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Rough night?', style: RiseText.title),
              const SizedBox(height: 6),
              Text(
                  'Marking a day keeps it from breaking your streak. It won\'t '
                  'add a day — it just protects what you\'ve built. Which day?',
                  style: RiseText.caption),
              const SizedBox(height: 16),
              _option(context, ref, sheetContext, 'Today', today,
                  excused.contains(today), const Key('rough-today')),
              const SizedBox(height: 10),
              _option(context, ref, sheetContext, 'Yesterday', yesterday,
                  excused.contains(yesterday), const Key('rough-yesterday')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _option(BuildContext context, WidgetRef ref, BuildContext sheetContext,
      String label, DateTime day, bool alreadyMarked, Key key) {
    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Navigator.of(sheetContext).pop();
        _mark(context, ref, day);
      },
      child: RiseCard(
        radius: RiseRadii.base,
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: RiseText.body.copyWith(fontWeight: FontWeight.w600)),
            ),
            if (alreadyMarked)
              Row(
                children: [
                  const Icon(Icons.check_circle,
                      color: RiseColors.positive, size: 18),
                  const SizedBox(width: 6),
                  Text('marked', style: RiseText.caption),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _mark(BuildContext context, WidgetRef ref, DateTime day) async {
    try {
      await ref.read(excusedDaysRepositoryProvider).excuse(day);
    } catch (_) {
      // Best-effort: a storage hiccup must never crash the Stats tab.
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Marked. Your streak\'s safe — rest up.')),
    );
  }
}

/// A tappable "share your progress" affordance. It hosts an offscreen
/// [ShareableStatsCard] inside a [RepaintBoundary]; on tap it rasterises that
/// card and hands it to the OS share sheet. A capture/share hiccup only ever
/// surfaces a gentle snackbar — sharing is a nicety, never load-bearing.
class _ShareCard extends ConsumerStatefulWidget {
  const _ShareCard({this.shareRunner});

  final Future<void> Function(GlobalKey boundaryKey)? shareRunner;

  @override
  ConsumerState<_ShareCard> createState() => _ShareCardState();
}

class _ShareCardState extends ConsumerState<_ShareCard> {
  final GlobalKey _boundaryKey = GlobalKey();
  bool _busy = false;

  /// The offscreen capture target only exists while a share is in flight, so it
  /// never duplicates the on-screen stats in the widget tree (or in tests).
  bool _capturing = false;

  Future<void> _share() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _capturing = true;
    });
    try {
      // Let the offscreen card build, lay out and paint before rasterising it.
      await WidgetsBinding.instance.endOfFrame;
      final runner = widget.shareRunner ??
          (key) => captureAndShare(key, text: 'My Rise wake-up stats');
      await runner(_boundaryKey);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Couldn\'t share right now. Try again.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _capturing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final streak = ref.watch(streakProvider);
    final events = ref.watch(wakeEventsProvider).value ?? const <WakeEvent>[];
    final earned = earnedAchievements(streak: streak, events: events)
        .where((b) => b.earned)
        .toList();
    final account = ref.watch(accountProvider).value;
    final handle = account?.username != null ? '@${account!.username}' : null;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          key: const Key('share-stats-card'),
          behavior: HitTestBehavior.opaque,
          onTap: _busy ? null : _share,
          child: RiseCard(
            child: Row(
              children: [
                const Icon(Icons.ios_share,
                    color: RiseColors.textDim, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Share your progress',
                          style: RiseText.body
                              .copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text('A clean card of your streak and badges.',
                          style: RiseText.caption),
                    ],
                  ),
                ),
                if (_busy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  const Icon(Icons.chevron_right,
                      color: RiseColors.textFaint, size: 20),
              ],
            ),
          ),
        ),
        // Offscreen capture target: laid out and painted (so toImage works) but
        // parked far off-screen, and only present while capturing so it never
        // duplicates the on-screen stats. Fixed size for a clean PNG.
        if (_capturing)
          Positioned(
            left: -10000,
            top: 0,
            width: kShareCardWidth,
            height: kShareCardHeight,
            child: RepaintBoundary(
              key: _boundaryKey,
              child: ShareableStatsCard(
                streakDays: streak.current,
                bestStreak: streak.best,
                consistency: consistencyScore(events),
                badges: earned,
                handle: handle,
              ),
            ),
          ),
      ],
    );
  }
}

/// The badges wall: every achievement, earned or locked. Badges reward what
/// you *did* (a streak, an early morning), never a label about who you are — and
/// a locked badge is framed as the next goal to reach, never a failure.
class _AchievementsSection extends ConsumerWidget {
  const _AchievementsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streak = ref.watch(streakProvider);
    final events = ref.watch(wakeEventsProvider).value ?? const <WakeEvent>[];
    final badges = earnedAchievements(streak: streak, events: events);
    final earned = badges.where((b) => b.earned).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SectionLabel('Achievements'),
            const Spacer(),
            Text('$earned / ${badges.length}',
                style: RiseText.mono(size: 12.5, color: RiseColors.textDim)),
          ],
        ),
        const SizedBox(height: 6),
        Text('Badges for what you did. Locked ones are simply what\'s next.',
            style: RiseText.caption),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 10.0;
            final tileWidth = (constraints.maxWidth - gap) / 2;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final b in badges)
                  SizedBox(width: tileWidth, child: _badgeTile(b)),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _badgeTile(Achievement a) {
    final earned = a.earned;
    final iconColor = earned ? RiseColors.primaryText : RiseColors.textFaint;
    final ringColor = earned ? RiseColors.positive : RiseColors.surface2;
    return RiseCard(
      radius: RiseRadii.base,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: ringColor,
                  shape: BoxShape.circle,
                  border: earned
                      ? null
                      : Border.all(color: RiseColors.border),
                ),
                child: Icon(_badgeIcon(a.id), size: 18, color: iconColor),
              ),
              const Spacer(),
              if (earned)
                const Icon(Icons.check_circle,
                    size: 18, color: RiseColors.positive),
            ],
          ),
          const SizedBox(height: 10),
          Text(a.title,
              style: RiseText.body.copyWith(
                  fontWeight: FontWeight.w700,
                  color: earned ? RiseColors.text : RiseColors.textDim)),
          const SizedBox(height: 2),
          Text(a.description,
              style: RiseText.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
          if (!earned && a.fraction != null) ...[
            const SizedBox(height: 10),
            _progressBar(a.fraction!),
            const SizedBox(height: 4),
            Text('${a.progress} / ${a.target}',
                style: RiseText.mono(size: 10.5, color: RiseColors.textFaint)),
          ],
        ],
      ),
    );
  }

  Widget _progressBar(double fraction) => ClipRRect(
        borderRadius: BorderRadius.circular(RiseRadii.pill),
        child: Container(
          height: 5,
          color: RiseColors.surface2,
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: fraction.clamp(0.0, 1.0),
            child: Container(color: RiseColors.textDim),
          ),
        ),
      );

  IconData _badgeIcon(String id) => switch (id) {
        'first_light' => Icons.wb_twilight,
        'streak_7' || 'streak_30' || 'streak_100' =>
          Icons.local_fire_department,
        'perfect_week' => Icons.verified_outlined,
        'no_snooze_week' => Icons.do_not_disturb_on_outlined,
        'early_bird' => Icons.wb_sunny_outlined,
        'sharp' => Icons.bolt,
        _ => Icons.emoji_events_outlined,
      };
}

/// The crew leaderboard on the Stats tab: own + crew ranked by wake
/// consistency. Signed out / unconfigured → a sign-in prompt.
class _LeaderboardSection extends ConsumerWidget {
  const _LeaderboardSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountProvider).value;
    if (account == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Crew leaderboard'),
          const SizedBox(height: 8),
          Text('Sign in from the Profile tab to rank up with your crew.',
              style: RiseText.caption),
        ],
      );
    }

    final board = ref.watch(leaderboardProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SectionLabel('Crew leaderboard'),
            const Spacer(),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => ref.invalidate(leaderboardProvider),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child:
                    Icon(Icons.refresh, size: 18, color: RiseColors.textDim),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        board.when(
          data: (standings) => standings.isEmpty
              ? Text('No leaderboard yet — add crew and start a streak.',
                  style: RiseText.caption)
              : Column(children: [
                  for (var i = 0; i < standings.length; i++)
                    _standingRow(i + 1, standings[i]),
                ]),
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          ),
          error: (_, __) => Row(
            children: [
              Expanded(
                child: Text('Could not load the leaderboard.',
                    style: RiseText.caption),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => ref.invalidate(leaderboardProvider),
                child: Text('Retry',
                    style: RiseText.caption.copyWith(
                        color: RiseColors.accent, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _standingRow(int rank, CrewStanding s) {
    final onTimePct = (s.stats.onTimeRate * 100).round();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(RiseSpacing.cardPad),
        decoration: BoxDecoration(
          color: s.isMe ? RiseColors.accentSoft : RiseColors.card,
          borderRadius: BorderRadius.circular(RiseRadii.base),
          border: Border.all(
              color: s.isMe ? RiseColors.accent : RiseColors.border),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: Text('$rank',
                  style: RiseText.mono(size: 15, weight: FontWeight.w600)),
            ),
            const SizedBox(width: 8),
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: avatarColorFromHex(s.avatarColor),
                  shape: BoxShape.circle),
              child: Text(
                (s.username.isNotEmpty ? s.username : '?')
                    .characters
                    .first
                    .toUpperCase(),
                style: RiseText.body.copyWith(
                    color: RiseColors.primaryText,
                    fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      s.displayName.isNotEmpty
                          ? s.displayName
                          : '@${s.username}',
                      style:
                          RiseText.body.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text('@${s.username} · $onTimePct% on time',
                      style: RiseText.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${s.stats.currentStreak}',
                    style: RiseText.mono(size: 18, weight: FontWeight.w600)),
                Text('day streak',
                    style: RiseText.caption.copyWith(fontSize: 10)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
