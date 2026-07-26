import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/consistency.dart';
import '../../domain/period_stats.dart';
import '../../domain/premium_feature.dart';
import '../../domain/wake_event.dart';
import '../../domain/wake_rhythm.dart';
import '../components/crew_entrance.dart';
import '../components/date_eyebrow.dart';
import '../components/rise_motion.dart';
import '../components/segmented.dart';
import '../components/stat_summary.dart';
import '../state/auth_providers.dart';
import '../state/entitlement_providers.dart';
import '../state/settings_providers.dart';
import '../state/wake_providers.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'paywall_screen.dart';
import 'stats/crew_lens.dart';
import 'stats/progress_lens.dart';
import 'stats/rhythm_lens.dart';

/// Which question the body is answering.
///
/// The old tab stacked twelve sections of identical weight in one scroll, so
/// nothing was skimmable and five unrelated scores never sat where they could
/// be compared. Now one summary answers "how am I doing?" in two seconds, and
/// each lens is a single screenful answering one follow-up. Nothing was
/// deleted — everything that used to be a section now lives in exactly one lens.
enum StatsLens { rhythm, progress, crew }

String statsLensLabel(StatsLens lens) => switch (lens) {
      StatsLens.rhythm => 'Rhythm',
      StatsLens.progress => 'Progress',
      StatsLens.crew => 'Crew',
    };

class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key, this.shareRunner, this.clock});

  /// Test seam: overrides the capture-and-share step so the failure UI can be
  /// exercised headlessly. Null in production.
  final Future<void> Function(GlobalKey boundaryKey)? shareRunner;

  /// Test seam: fixes "now" so the rhythm window is deterministic.
  final DateTime? clock;

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  StatsLens _lens = StatsLens.rhythm;
  StatsPeriod _period = StatsPeriod.week;

  @override
  Widget build(BuildContext context) {
    final now = widget.clock ?? DateTime.now();
    final streak = ref.watch(streakProvider);
    final events = ref.watch(wakeEventsProvider).valueOrNull ?? const <WakeEvent>[];
    final use24h =
        ref.watch(currentSettingsProvider.select((s) => s.use24HourTime));

    // Best-effort like streakProvider: an unavailable excused-days store must
    // never take the Stats tab down.
    Set<DateTime> excused;
    try {
      excused = ref.watch(excusedDaysProvider).valueOrNull ?? const <DateTime>{};
    } catch (_) {
      excused = const <DateTime>{};
    }

    // Computed once for the whole build: the summary's week marks, the Rhythm
    // lens's chart and its grid all read the same days, so they can never
    // disagree about a morning.
    final fortnight = buildRhythm(events, now,
        days: 14,
        excusedDays: excused,
        freezeAbsorbed: streak.freezeAbsorbed);
    final week = fortnight.sublist(fortnight.length - 7);
    final stats = aggregatePeriod(events, now, _period);
    final periodsLocked = !ref
        .watch(premiumGateProvider)
        .canUse(PremiumFeature.monthlyYearlyStats);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            RiseSpacing.screen, 8, RiseSpacing.screen, 40),
        children: [
          CrewEntrance(
            index: 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const DateEyebrow(),
                const SizedBox(height: 3),
                Text('Your mornings', style: RiseText.display),
              ],
            ),
          ),
          const SizedBox(height: 16),
          CrewEntrance(
            index: 1,
            child: StatSummary(
              streak: streak,
              week: week,
              stats: stats,
              consistency: consistencyScore(events),
              period: _period,
              periodsLocked: periodsLocked,
              use24h: use24h,
              onPeriod: (p) {
                // Weekly stays free; the longer views are premium. Locked →
                // the paywall, and the view stays where it was.
                if (p != StatsPeriod.week && periodsLocked) {
                  openPaywall(context);
                  return;
                }
                setState(() => _period = p);
              },
            ),
          ),
          const SizedBox(height: 20),
          CrewEntrance(
            index: 2,
            child: SegmentedControl<StatsLens>(
              segments: [
                for (final l in StatsLens.values)
                  (value: l, label: statsLensLabel(l)),
              ],
              selected: _lens,
              onChanged: (l) => setState(() => _lens = l),
            ),
          ),
          const SizedBox(height: 4),
          // Only the active lens is in the tree: two thirds of what used to
          // build on every frame of a long scroll simply is not built.
          RiseFade(
            child: RiseFade.keyed(_lens.name, _body(now, events, fortnight)),
          ),
        ],
      ),
    );
  }

  Widget _body(
          DateTime now, List<WakeEvent> events, List<RhythmDay> fortnight) =>
      switch (_lens) {
        StatsLens.rhythm =>
          RhythmLens(now: now, events: events, fortnight: fortnight),
        StatsLens.progress => ProgressLens(
            now: now, events: events, shareRunner: widget.shareRunner),
        StatsLens.crew => const CrewLens(),
      };
}

/// Kept for the account-less case: the Crew lens explains itself, but the
/// screen still needs to know whether anyone is signed in.
bool statsHasAccount(WidgetRef ref) =>
    ref.watch(accountProvider).valueOrNull != null;
