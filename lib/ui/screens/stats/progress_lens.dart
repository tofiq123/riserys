import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/excused_days_repository.dart';
import '../../../data/nudge/nudge_service.dart';
import '../../../domain/achievements.dart';
import '../../../domain/alertness_trend.dart';
import '../../../domain/crew_member.dart';
import '../../../domain/consistency.dart';
import '../../../domain/crew_state.dart';
import '../../../domain/premium_feature.dart';
import '../../../domain/streak.dart';
import '../../../domain/streak_risk.dart';
import '../../../domain/wake_event.dart';
import '../../components/medallion_rail.dart';
import '../../components/premium_lock_card.dart';
import '../../components/rise_card.dart';
import '../../components/rise_disclaimer.dart';
import '../../components/rise_motion.dart';
import '../../components/rise_spinner.dart';
import '../../components/section_label.dart';
import '../../components/shareable_stats_card.dart';
import '../../components/sparkline.dart';
import '../../components/toast.dart';
import '../../share/stats_share.dart';
import '../../state/auth_providers.dart';
import '../../state/crew_providers.dart';
import '../../state/entitlement_providers.dart';
import '../../state/nudge_providers.dart';
import '../../state/wake_providers.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../paywall_screen.dart';

/// "Am I building something?"
///
/// The streak and what it is worth: the risk banner when the run is on the
/// line, the run itself, the badges as a rail rather than a wall, and the
/// alertness read with its disclaimer intact.
class ProgressLens extends ConsumerWidget {
  const ProgressLens({
    super.key,
    required this.now,
    required this.events,
    this.shareRunner,
  });

  final DateTime now;
  final List<WakeEvent> events;
  final Future<void> Function(GlobalKey boundaryKey)? shareRunner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streak = ref.watch(streakProvider);
    final scored = [
      for (final e in events)
        if (e.alertnessScore != null) e
    ]..sort((a, b) => a.firstRingAt.compareTo(b.firstRingAt));
    final trendUnlocked =
        ref.watch(premiumGateProvider).canUse(PremiumFeature.alertnessHistory);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StreakRiskBanner(),
        const SizedBox(height: 24),
        const SectionLabel('Streak'),
        const SizedBox(height: 12),
        _streakCard(streak),
        const SizedBox(height: 24),
        _AchievementsRail(streak: streak, events: events),
        const SizedBox(height: 24),
        const SectionLabel('Alertness'),
        const SizedBox(height: 12),
        _alertnessCard(scored),
        ..._trend(context, scored, locked: !trendUnlocked),
        const SizedBox(height: 12),
        const RiseDisclaimer(
            text: 'Your Alertness Score is a wellness insight, not a '
                'medical measure.'),
        const SizedBox(height: 24),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Expanded(child: _RoughNightCard()),
              const SizedBox(width: 10),
              Expanded(child: _ShareCard(shareRunner: shareRunner)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _streakCard(StreakStats streak) {
    // The run day by day, from the same fold that produced the number above —
    // so a break and the climb back are both visible and cannot disagree.
    final runs = streak.runSeries(now, days: 30);
    return RiseCard(
      padding: const EdgeInsets.all(RiseSpacing.screen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _figure('${streak.current}', 'current'),
              _figure('${streak.best}', 'best'),
              _figure('${streak.freezesRemaining}',
                  streak.freezesRemaining == 1 ? 'freeze left' : 'freezes left'),
            ],
          ),
          if (runs.any((r) => r > 0)) ...[
            const SizedBox(height: 18),
            Sparkline(
              values: [for (final r in runs) r.toDouble()],
              color: RiseColors.text,
              height: 44,
            ),
            const SizedBox(height: 8),
            Text('Your run, day by day, over the last 30.',
                style: RiseText.caption),
          ],
        ],
      ),
    );
  }

  Widget _figure(String value, String label) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: RiseText.mono(size: 24, weight: FontWeight.w600),
                maxLines: 1),
            const SizedBox(height: 4),
            Text(label,
                style: RiseText.caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      );

  /// Reaction-speed alertness: latest score, average and a small recent trend.
  /// Honest, non-diagnostic framing of raw PVT performance — never a medical or
  /// sleep-stage claim.
  Widget _alertnessCard(List<WakeEvent> scored) {
    if (scored.isEmpty) {
      return RiseCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 8),
          child: Column(
            children: [
              Icon(Icons.bolt_outlined, size: 34, color: RiseColors.textFaint),
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
    final recent =
        scored.length > 9 ? scored.sublist(scored.length - 9) : scored;

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
                  style: RiseText.mono(size: 40, weight: FontWeight.w600)),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: _bandChip(latest),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$avg',
                      style: RiseText.mono(size: 20, weight: FontWeight.w600)),
                  Text('avg', style: RiseText.caption.copyWith(fontSize: 10)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text('latest score', style: RiseText.caption),
          const SizedBox(height: 14),
          Sparkline(
            values: [for (final e in recent) e.alertnessScore!.toDouble()],
            color: RiseColors.text,
            height: 40,
          ),
          const SizedBox(height: 12),
          Text(
              'Your reaction speed at wake-up — sharper is more awake. '
              'Not a medical measure.',
              style: RiseText.caption),
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

  // Neutral, informational colours: green (sharp), amber (steady), indigo
  // (groggy). Deliberately NOT red — a low score is information, never a
  // failure to be shamed.
  Color _bandColor(int score) {
    if (score >= 80) return RiseColors.positive;
    if (score >= 50) return RiseColors.waking;
    return RiseColors.asleep;
  }

  /// A longer-horizon trend beyond the single card. Hidden until there are
  /// enough scores for a direction to mean anything.
  List<Widget> _trend(BuildContext context, List<WakeEvent> scored,
      {required bool locked}) {
    if (scored.length < kMinTrendScores) return const [];
    if (locked) {
      return [
        const SizedBox(height: 12),
        premiumLockCard(context, 'Alertness history & trends'),
      ];
    }
    final recent =
        scored.length > 14 ? scored.sublist(scored.length - 14) : scored;
    final scores = [for (final e in recent) e.alertnessScore!];
    final trend = alertnessTrendOf(scores);

    return [
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
                        fontWeight: FontWeight.w700,
                        color: _trendColor(trend))),
                const Spacer(),
                Text('last ${recent.length}',
                    style: RiseText.caption.copyWith(fontSize: 10)),
              ],
            ),
            const SizedBox(height: 10),
            Text(_trendLine(trend), style: RiseText.caption),
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
        AlertnessTrend.steady =>
          'Your wake-up reaction speed is holding steady.',
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
}

/// The badges wall, as a rail. Badges reward what you *did* — never a label
/// about who you are — and a locked badge is framed as the next goal, not a
/// failure.
class _AchievementsRail extends StatelessWidget {
  const _AchievementsRail({required this.streak, required this.events});

  final StreakStats streak;
  final List<WakeEvent> events;

  @override
  Widget build(BuildContext context) {
    final badges = earnedAchievements(streak: streak, events: events);
    final earned = badges.where((b) => b.earned).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SectionLabel('Badges'),
            const Spacer(),
            Text('$earned / ${badges.length}',
                style: RiseText.mono(size: 12.5, color: RiseColors.textDim)),
          ],
        ),
        const SizedBox(height: 6),
        Text("Badges for what you did. Locked ones are simply what's next.",
            style: RiseText.caption),
        const SizedBox(height: 12),
        MedallionRail(
          badges: badges,
          onTap: (b) => _showBadge(context, b),
        ),
      ],
    );
  }

  void _showBadge(BuildContext context, Achievement badge) {
    showModalBottomSheet<void>(
      context: context,
      barrierColor: RiseColors.scrim,
      backgroundColor: RiseColors.card,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(RiseSpacing.screen),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(badge.title, style: RiseText.title),
              const SizedBox(height: 6),
              Text(badge.description, style: RiseText.caption),
              if (!badge.earned && badge.target != null) ...[
                const SizedBox(height: 12),
                Text('${badge.progress} of ${badge.target}',
                    style: RiseText.mono(size: 13)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A gentle, opt-in accountability prompt: when the run is on the line today or
/// just reset, a one-tap, pro-social way to tell the crew. Framed as
/// encouragement, never shame. Hidden entirely unless signed in, with crew, and
/// with a moment worth prompting — so it degrades to nothing without a backend.
class _StreakRiskBanner extends ConsumerStatefulWidget {
  const _StreakRiskBanner();

  @override
  ConsumerState<_StreakRiskBanner> createState() => _StreakRiskBannerState();
}

class _StreakRiskBannerState extends ConsumerState<_StreakRiskBanner> {
  bool _sending = false;

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(accountProvider).valueOrNull;
    if (account == null) return const SizedBox.shrink();
    final crew = ref.watch(crewProvider).valueOrNull ?? CrewState.empty;
    if (crew.friends.isEmpty) return const SizedBox.shrink();
    final risk = streakRisk(ref.watch(streakProvider), DateTime.now());
    if (risk == StreakRisk.none) return const SizedBox.shrink();

    final broke = risk == StreakRisk.broke;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: RisePressable(
        key: const Key('accountability-ping-card'),
        onTap: _sending ? null : () => _confirm(crew.friends, broke),
        child: Container(
          padding: const EdgeInsets.all(RiseSpacing.cardPad),
          decoration: BoxDecoration(
            color: RiseColors.card,
            borderRadius: BorderRadius.circular(RiseRadii.base),
            border: Border.all(color: RiseColors.waking),
            boxShadow: RiseShadows.card,
          ),
          child: Row(
            children: [
              Icon(broke ? Icons.wb_twilight : Icons.local_fire_department,
                  color: RiseColors.waking, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(broke ? 'Back on it' : 'Keep your streak alive',
                        style:
                            RiseText.body.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                        broke
                            ? 'Streaks break — getting back up is the point. '
                                "Tell your crew you're on it."
                            : "It's on the line today. Lean on your crew to "
                                'stay accountable.',
                        style: RiseText.caption),
                  ],
                ),
              ),
              if (_sending)
                const RiseSpinner(size: 18)
              else
                Icon(Icons.chevron_right,
                    color: RiseColors.textFaint, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _confirm(List<CrewMember> friends, bool broke) {
    showModalBottomSheet<void>(
      context: context,
      barrierColor: RiseColors.scrim,
      backgroundColor: RiseColors.card,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(RiseSpacing.screen),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  broke
                      ? "Let your crew know you're back on it?"
                      : 'Rally your crew?',
                  style: RiseText.title),
              const SizedBox(height: 6),
              Text(
                  "We'll give your crew a friendly heads-up that you're on "
                  'your wake-ups. A little accountability — no pressure, no '
                  'shame.',
                  style: RiseText.caption),
              const SizedBox(height: 18),
              GestureDetector(
                key: const Key('accountability-ping-confirm'),
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _send(friends);
                },
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    color: RiseColors.primary,
                    borderRadius: BorderRadius.circular(RiseRadii.sm),
                  ),
                  child: Text('Let my crew know',
                      style: RiseText.body.copyWith(
                          color: RiseColors.primaryText,
                          fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 10),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(sheetContext).pop(),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('Not now',
                      style: RiseText.body.copyWith(color: RiseColors.textDim)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _send(List<CrewMember> friends) async {
    if (_sending) return;
    setState(() => _sending = true);
    final nudge = ref.read(nudgeServiceProvider);
    var sent = 0;
    for (final m in friends) {
      try {
        // The accountability "I'm back on it" ping — server composes the fixed
        // backup copy from this kind (never client text).
        await nudge.nudge(m.id, kind: NudgeKind.backup);
        sent++;
      } on NudgeException {
        // Best-effort per member (e.g. rate-limited) — keep going.
      } catch (_) {
        // Ignore and continue; this is a nicety, never load-bearing.
      }
    }
    if (!mounted) return;
    setState(() => _sending = false);
    RiseToast.show(
      context,
      sent > 0
          ? "Your crew knows you're on it. 💪"
          : "Couldn't reach your crew right now. Try again later.",
      kind: sent > 0 ? RiseToastKind.success : RiseToastKind.error,
    );
  }
}

/// A compact half-width action: icon, short title, one-line caption.
class _ActionTile extends StatelessWidget {
  const _ActionTile({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.caption,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String caption;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return RisePressable(
      onTap: onTap,
      child: RiseCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor, size: 20),
                const Spacer(),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 10),
            Text(title,
                style: RiseText.body.copyWith(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(caption,
                style: RiseText.caption,
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

/// A gentle, no-penalty affordance: mark a recent day as a "rough night" so it
/// does not break the streak. Rest is framed as legitimate, never as a failure.
/// An excused day only protects the streak; it never advances it, so there is
/// nothing to game.
class _RoughNightCard extends ConsumerWidget {
  const _RoughNightCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Set<DateTime> excused;
    try {
      excused = ref.watch(excusedDaysProvider).valueOrNull ?? const <DateTime>{};
    } catch (_) {
      excused = const <DateTime>{};
    }
    final today = ExcusedDaysRepository.dayOf(DateTime.now());
    final yesterday = today.subtract(const Duration(days: 1));

    return _ActionTile(
      key: const Key('rough-night-card'),
      icon: Icons.bedtime_outlined,
      iconColor: RiseColors.asleep,
      title: 'Rough night?',
      caption: 'Mark it — your streak stays safe.',
      onTap: () => _showSheet(context, ref, today, yesterday, excused),
    );
  }

  void _showSheet(BuildContext context, WidgetRef ref, DateTime today,
      DateTime yesterday, Set<DateTime> excused) {
    showModalBottomSheet<void>(
      context: context,
      barrierColor: RiseColors.scrim,
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
                  "Marking a day keeps it from breaking your streak. It won't "
                  "add a day — it just protects what you've built. Which day?",
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
                  Icon(Icons.check_circle, color: RiseColors.positive, size: 18),
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
    RiseToast.show(context, "Marked. Your streak's safe — rest up.",
        kind: RiseToastKind.success);
  }
}

/// A tappable "share your progress" affordance. It hosts an offscreen
/// [ShareableStatsCard] inside a [RepaintBoundary]; on tap it rasterises that
/// card and hands it to the OS share sheet. A capture/share hiccup only ever
/// surfaces a gentle toast — sharing is a nicety, never load-bearing.
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
          (key) => captureAndShare(key, text: 'My Riserys wake-up stats');
      await runner(_boundaryKey);
    } catch (_) {
      if (mounted) {
        RiseToast.show(context, "Couldn't share right now. Try again.",
            kind: RiseToastKind.error);
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
    final events =
        ref.watch(wakeEventsProvider).valueOrNull ?? const <WakeEvent>[];
    final account = ref.watch(accountProvider).valueOrNull;
    final handle = account?.username != null ? '@${account!.username}' : null;
    final locked =
        !ref.watch(premiumGateProvider).canUse(PremiumFeature.shareableCard);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        _ActionTile(
          key: const Key('share-stats-card'),
          icon: Icons.ios_share,
          iconColor: RiseColors.textDim,
          title: 'Share your progress',
          caption: 'A clean card of your streak.',
          trailing: _busy
              ? const RiseSpinner(size: 16)
              : (locked
                  ? Icon(Icons.lock_outline, color: RiseColors.textDim, size: 16)
                  : null),
          onTap: _busy ? null : (locked ? () => openPaywall(context) : _share),
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
                badges: earnedAchievements(streak: streak, events: events)
                    .where((b) => b.earned)
                    .toList(),
                handle: handle,
              ),
            ),
          ),
      ],
    );
  }
}
