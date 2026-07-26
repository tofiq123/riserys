import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/crew_member.dart';
import '../../../domain/crew_score.dart';
import '../../../domain/crew_standing.dart';
import '../../components/crew_avatar.dart';
import '../../components/hero_card.dart';
import '../../components/podium.dart';
import '../../components/rise_motion.dart';
import '../../components/rise_skeleton.dart';
import '../../components/section_label.dart';
import '../../state/auth_providers.dart';
import '../../state/leaderboard_providers.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../friend_detail_screen.dart';

/// "How do I compare?"
///
/// A podium for the three places worth celebrating, then compact rows. Your own
/// row is highlighted wherever it falls — and pinned into view when you are
/// outside the top, so the answer is never below the fold.
class CrewLens extends ConsumerWidget {
  const CrewLens({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountProvider).valueOrNull;
    if (account == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('Crew leaderboard'),
            const SizedBox(height: 8),
            Text('Sign in from the Profile tab to rank up with your crew.',
                style: RiseText.caption),
          ],
        ),
      );
    }

    final board = ref.watch(leaderboardProvider);
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SectionLabel('Crew leaderboard'),
              const Spacer(),
              Semantics(
                button: true,
                label: 'Refresh leaderboard',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => ref.invalidate(leaderboardProvider),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child:
                        Icon(Icons.refresh, size: 18, color: RiseColors.textDim),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          RiseFade(
            child: board.when(
              loading: () => const _BoardSkeleton(),
              error: (_, __) => _Failed(
                  onRetry: () => ref.invalidate(leaderboardProvider)),
              data: (standings) => standings.isEmpty
                  ? RiseFade.keyed(
                      'empty',
                      Text(
                          'No leaderboard yet — add crew and start a streak.',
                          style: RiseText.caption))
                  : RiseFade.keyed('data', _Board(standings: standings)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Board extends StatelessWidget {
  const _Board({required this.standings});

  final List<CrewStanding> standings;

  void _open(BuildContext context, CrewStanding s) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => FriendDetailScreen(
        member: CrewMember(
          id: s.id,
          username: s.username,
          displayName: s.displayName,
          avatarColor: s.avatarColor,
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final rest = standings.length > 3 ? standings.sublist(3) : const <CrewStanding>[];
    // If you are outside the podium AND outside the rows we show, your own row
    // still appears — the one row nobody should have to hunt for.
    final me = standings.firstWhere((s) => s.isMe,
        orElse: () => standings.first);
    final meShown = standings.indexOf(me) < 3 || rest.contains(me);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Podium(top: standings, onTap: (s) => _open(context, s)),
        if (rest.isNotEmpty) const SizedBox(height: 18),
        for (var i = 0; i < rest.length; i++)
          _Row(
            rank: i + 4,
            standing: rest[i],
            onTap: rest[i].isMe ? null : () => _open(context, rest[i]),
          ),
        if (!meShown && me.isMe) ...[
          const SizedBox(height: 6),
          _Row(rank: standings.indexOf(me) + 1, standing: me),
        ],
        const SizedBox(height: 14),
        _crewScore(computeCrewScore(standings)),
      ],
    );
  }

  /// One shared total the whole crew grows together, plus your own contribution
  /// to it. Individuals stay ranked above — together, that is the research's
  /// individual-plus-group model.
  Widget _crewScore(CrewScore score) {
    final you = score.you;
    return HeroCard(
      eyebrow: 'CREW SCORE',
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: RiseCountUp(
                  value: score.crewTotal,
                  style: RiseText.mono(
                      size: 34,
                      weight: FontWeight.w600,
                      color: RiseColors.primaryText,
                      letterSpacing: -1),
                ),
              ),
              const SizedBox(width: 9),
              Flexible(
                child: Opacity(
                  opacity: 0.75,
                  child: Text('together',
                      style: RiseText.body.copyWith(
                          color: RiseColors.primaryText, fontSize: 14),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.fade),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Opacity(
            opacity: 0.75,
            child: Text(
                you == null
                    ? '${score.memberCount} in your crew, climbing together.'
                    : 'Your part: ${you.points} pts · ${you.sharePercent}% of '
                        'the crew.',
                style:
                    RiseText.caption.copyWith(color: RiseColors.primaryText)),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.rank, required this.standing, this.onTap});

  final int rank;
  final CrewStanding standing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = standing;
    final pct = s.stats.totalWakes == 0
        ? 'no wakes yet'
        : '${(s.stats.onTimeRate * 100).round()}% on time';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RisePressable(
        key: Key('standing-${s.id}'),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(RiseSpacing.cardPad),
          decoration: BoxDecoration(
            color: s.isMe ? RiseColors.accentSoft : RiseColors.card,
            borderRadius: BorderRadius.circular(RiseRadii.base),
            border: Border.all(
                color: s.isMe ? RiseColors.accent : RiseColors.border),
            boxShadow: RiseShadows.card,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: Text('$rank',
                    style: RiseText.mono(size: 14, weight: FontWeight.w600)),
              ),
              const SizedBox(width: 6),
              CrewAvatar(
                  username: s.username, colorHex: s.avatarColor, size: 32),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        s.isMe
                            ? 'You'
                            : (s.displayName.isNotEmpty
                                ? s.displayName
                                : '@${s.username}'),
                        style: RiseText.body.copyWith(
                            fontSize: 13.5, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text('@${s.username} · $pct',
                        style: RiseText.caption.copyWith(fontSize: 11.5),
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
                      style: RiseText.mono(size: 17, weight: FontWeight.w600)),
                  Text('day run',
                      style: RiseText.caption.copyWith(fontSize: 10)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BoardSkeleton extends StatelessWidget {
  const _BoardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('leaderboard-loading'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Mirrors the podium's silhouette so nothing jumps when it lands.
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final h in [90.0, 104.0, 80.0])
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.5),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RiseSkeletonCircle(size: h == 104.0 ? 44 : 36),
                    const SizedBox(height: 9),
                    RiseSkeleton(width: 96, height: h, radius: RiseRadii.base),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 18),
        for (var i = 0; i < 2; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(RiseSpacing.cardPad),
              decoration: BoxDecoration(
                color: RiseColors.card,
                borderRadius: BorderRadius.circular(RiseRadii.base),
                border: Border.all(color: RiseColors.border),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 26),
                  const RiseSkeletonCircle(size: 32),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        RiseSkeleton(width: 110, height: 12),
                        SizedBox(height: 7),
                        RiseSkeleton(width: 150, height: 10),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const ValueKey('leaderboard-error'),
      children: [
        Expanded(
          child:
              Text('Could not load the leaderboard.', style: RiseText.caption),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onRetry,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Text('Retry',
                style: RiseText.caption.copyWith(
                    color: RiseColors.accent, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }
}
