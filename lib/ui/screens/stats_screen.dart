import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/streak.dart';
import '../../domain/wake_event.dart';
import '../components/rise_card.dart';
import '../components/section_label.dart';
import '../state/wake_providers.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

DateTime _todayLocal(DateTime now) {
  final l = now.toLocal();
  return DateTime(l.year, l.month, l.day);
}

DateTime _dayOf(DateTime t) {
  final l = t.toLocal();
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
    final d = _dayOf(e.firstRingAt);
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
          ],
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
              Text('Set an alarm and wake up on time to start your streak.',
                  textAlign: TextAlign.center, style: RiseText.caption),
            ],
          ),
        ),
      );

  Widget _streakCard(StreakStats s) => RiseCard(
        padding: const EdgeInsets.all(20),
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
}
