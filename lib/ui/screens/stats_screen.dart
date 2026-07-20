import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/excused_days_repository.dart';
import '../../domain/crew_standing.dart';
import '../../domain/streak.dart';
import '../../domain/wake_event.dart';
import '../components/rise_card.dart';
import '../components/section_label.dart';
import '../state/auth_providers.dart';
import '../state/leaderboard_providers.dart';
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
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streak = ref.watch(streakProvider);
    final events = ref.watch(wakeEventsProvider).value ?? const <WakeEvent>[];
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
            const SectionLabel('Alertness'),
            const SizedBox(height: 12),
            _alertnessCard(events),
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
