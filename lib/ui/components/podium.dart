import 'package:flutter/widgets.dart';

import '../../domain/crew_standing.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'crew_avatar.dart';
import 'rise_motion.dart';

/// The top of a leaderboard, as a podium: second, first, third — with first in
/// the middle on the tallest plinth.
///
/// A ranked list answers "who is where"; a podium answers "who is winning" in
/// one glance, which is the question people actually open a leaderboard with.
/// Everyone from fourth down stays a compact row underneath.
///
/// Degrades honestly: two standings render two plinths, one renders one. It
/// never fakes an empty place.
class Podium extends StatelessWidget {
  const Podium({super.key, required this.top, this.onTap});

  /// Up to three standings, already ranked best-first.
  final List<CrewStanding> top;
  final void Function(CrewStanding)? onTap;

  /// Minimums, not fixed heights: the plinth still steps down by place, but a
  /// long name or a four-digit run makes it taller rather than clipping.
  static const _heights = {1: 104.0, 2: 90.0, 3: 80.0};
  static const _labels = {1: '1ST', 2: '2ND', 3: '3RD'};

  @override
  Widget build(BuildContext context) {
    if (top.isEmpty) return const SizedBox.shrink();
    final three = top.take(3).toList();

    // Display order puts the winner in the middle once there are three.
    final order = switch (three.length) {
      1 => [0],
      2 => [0, 1],
      _ => [1, 0, 2],
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final i in order) ...[
          if (i != order.first) const SizedBox(width: 9),
          Flexible(
            child: _Plinth(
              standing: three[i],
              place: i + 1,
              height: _heights[i + 1]!,
              label: _labels[i + 1]!,
              onTap: onTap == null || three[i].isMe
                  ? null
                  : () => onTap!(three[i]),
            ),
          ),
        ],
      ],
    );
  }
}

class _Plinth extends StatelessWidget {
  const _Plinth({
    required this.standing,
    required this.place,
    required this.height,
    required this.label,
    this.onTap,
  });

  final CrewStanding standing;
  final int place;
  final double height;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final winner = place == 1;
    final ink = winner ? RiseColors.primaryText : RiseColors.text;
    final dim = winner
        ? RiseColors.primaryText.withValues(alpha: 0.65)
        : RiseColors.textDim;

    return RisePressable(
      key: Key('podium-${standing.id}'),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 116),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CrewAvatar(
              username: standing.username,
              colorHex: standing.avatarColor,
              size: winner ? 44 : 36,
            ),
            const SizedBox(height: 9),
            Container(
              constraints: BoxConstraints(minHeight: height),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 10),
              decoration: BoxDecoration(
                color: winner ? RiseColors.primary : RiseColors.card,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(RiseRadii.base),
                    bottom: Radius.circular(RiseRadii.sm)),
                border: Border.all(
                    color: winner ? RiseColors.primary : RiseColors.border),
                boxShadow: winner ? RiseShadows.primary : RiseShadows.card,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label,
                      style: RiseText.mono(
                          size: 10.5, weight: FontWeight.w600, color: dim)),
                  const SizedBox(height: 6),
                  Text(
                    standing.isMe
                        ? 'You'
                        : (standing.displayName.isNotEmpty
                            ? standing.displayName.split(' ').first
                            : '@${standing.username}'),
                    style: RiseText.body.copyWith(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 7),
                  Text('🔥${standing.stats.currentStreak}',
                      style: RiseText.mono(
                          size: 14, weight: FontWeight.w600, color: ink),
                      maxLines: 1),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
