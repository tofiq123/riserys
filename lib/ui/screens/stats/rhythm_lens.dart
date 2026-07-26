import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/rise_settings.dart';
import '../../../domain/wake_event.dart';
import '../../../domain/wake_insights.dart';
import '../../../domain/wake_rhythm.dart';
import '../../components/consistency_grid.dart';
import '../../components/rise_card.dart';
import '../../components/section_label.dart';
import '../../components/wake_evidence_card.dart';
import '../../components/wake_rhythm_chart.dart';
import '../../state/settings_providers.dart';
import '../../state/wake_providers.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

/// "When do I actually get up?"
///
/// The chart that used to live here plotted *minutes late*, which cannot answer
/// that question. This one puts clock time on the y axis and draws each day's
/// on-time window as a band, so the shape of a week is readable at a glance and
/// a mark inside the band is on time by construction.
class RhythmLens extends ConsumerWidget {
  const RhythmLens({
    super.key,
    required this.now,
    required this.events,
    required this.fortnight,
  });

  final DateTime now;
  final List<WakeEvent> events;

  /// The same fourteen days the summary block's week marks came from.
  final List<RhythmDay> fortnight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final evidence = ref.watch(wakeEvidenceProvider);
    final streak = ref.watch(streakProvider);
    Set<DateTime> excused;
    try {
      excused = ref.watch(excusedDaysProvider).valueOrNull ?? const <DateTime>{};
    } catch (_) {
      excused = const <DateTime>{};
    }

    final weeks = buildRhythmWeeks(events, now,
        weeks: 5,
        excusedDays: excused,
        freezeAbsorbed: streak.freezeAbsorbed);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The freshest, most personal read stays first — it is about the
        // morning that just happened.
        if (evidence != null) ...[
          const SizedBox(height: 16),
          WakeEvidenceCard(evidence: evidence),
        ],
        const SizedBox(height: 24),
        const SectionLabel('When you actually get up'),
        const SizedBox(height: 12),
        RiseCard(
          padding: const EdgeInsets.all(RiseSpacing.screen),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              WakeRhythmChart(
                  days: fortnight, use24h: settings.use24HourTime),
              if (settledDays(fortnight).isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(height: 1, color: RiseColors.divider),
                const SizedBox(height: 12),
                Text(rhythmSummary(fortnight), style: RiseText.caption),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        const SectionLabel('Five weeks'),
        const SizedBox(height: 12),
        RiseCard(
          padding: const EdgeInsets.all(RiseSpacing.screen),
          child: ConsistencyGrid(days: weeks),
        ),
        ..._patterns(events, settings),
      ],
    );
  }

  /// Honest, plain-language observations from the wake log — shown only once
  /// there's enough data to be meaningful. Never diagnostic or judgemental.
  List<Widget> _patterns(List<WakeEvent> events, RiseSettings settings) {
    final insights = buildWakeInsights(events,
        targetWakeHour: settings.targetWakeHour,
        targetWakeMinute: settings.targetWakeMinute,
        use24h: settings.use24HourTime);
    if (insights.isEmpty) return const [];
    return [
      const SizedBox(height: 24),
      const SectionLabel('Patterns'),
      const SizedBox(height: 6),
      Text('A few honest observations — not judgements.',
          style: RiseText.caption),
      const SizedBox(height: 12),
      RiseCard(
        padding: const EdgeInsets.all(RiseSpacing.screen),
        child: Column(
          children: [
            for (var i = 0; i < insights.length; i++)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
                child: Column(
                  children: [
                    if (i > 0) ...[
                      Container(height: 1, color: RiseColors.divider),
                      const SizedBox(height: 12),
                    ],
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(_icon(insights[i].kind),
                            size: 18, color: RiseColors.textDim),
                        const SizedBox(width: 11),
                        Expanded(
                            child: Text(insights[i].text,
                                style: RiseText.body.copyWith(height: 1.4))),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ];
  }

  static IconData _icon(WakeInsightKind kind) => switch (kind) {
        WakeInsightKind.onTime => Icons.check_circle_outline,
        WakeInsightKind.goal => Icons.wb_sunny_outlined,
        WakeInsightKind.weekdayWeekend => Icons.calendar_today_outlined,
        WakeInsightKind.consistentDay => Icons.event_available_outlined,
      };
}
