import 'package:flutter/material.dart';

import '../../domain/achievements.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'rise_motion.dart';

/// Achievements as a horizontal rail rather than a two-column wall.
///
/// Eight badge cards stacked vertically pushed everything below them off the
/// screen and gave a locked badge the same weight as an earned one. Here the
/// earned ones lead, the nearest unearned one carries its progress, and the
/// rest queue up behind — one swipe instead of one screenful.
class MedallionRail extends StatelessWidget {
  const MedallionRail({super.key, required this.badges, this.onTap});

  final List<Achievement> badges;
  final void Function(Achievement)? onTap;

  static const double height = 138;

  /// Earned first, then the closest unearned (so "what's next" is visible
  /// without scrolling), then the rest by how near they are.
  List<Achievement> get ordered {
    final earned = [for (final b in badges) if (b.earned) b];
    final locked = [for (final b in badges) if (!b.earned) b]
      ..sort((a, b) => (b.fraction ?? 0).compareTo(a.fraction ?? 0));
    return [...earned, ...locked];
  }

  @override
  Widget build(BuildContext context) {
    final list = ordered;
    final nextId = list.firstWhere((b) => !b.earned,
        orElse: () => const Achievement(
            id: '', title: '', description: '', earned: true)).id;

    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: const EdgeInsets.only(bottom: 4),
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) => _Medallion(
          badge: list[i],
          isNext: list[i].id == nextId && nextId.isNotEmpty,
          onTap: onTap == null ? null : () => onTap!(list[i]),
        ),
      ),
    );
  }
}

class _Medallion extends StatelessWidget {
  const _Medallion({required this.badge, required this.isNext, this.onTap});

  final Achievement badge;
  final bool isNext;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final earned = badge.earned;
    return RisePressable(
      key: Key('medallion-${badge.id}'),
      onTap: onTap,
      child: Container(
        width: 108,
        padding: const EdgeInsets.fromLTRB(11, 13, 11, 11),
        decoration: BoxDecoration(
          color: RiseColors.card,
          borderRadius: BorderRadius.circular(RiseRadii.base),
          border: Border.all(
              color: isNext ? RiseColors.waking : RiseColors.border),
          boxShadow: RiseShadows.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: earned ? RiseColors.primary : RiseColors.surface2,
                shape: BoxShape.circle,
                border: earned ? null : Border.all(color: RiseColors.border),
              ),
              child: Icon(
                _icon(badge.id),
                size: 19,
                color: earned ? RiseColors.primaryText : RiseColors.textDim,
              ),
            ),
            const SizedBox(height: 9),
            Text(badge.title,
                textAlign: TextAlign.center,
                style: RiseText.body.copyWith(
                    fontSize: 11.5,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    color: earned ? RiseColors.text : RiseColors.textDim),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            const Spacer(),
            if (earned)
              Text('earned',
                  style: RiseText.mono(
                      size: 10,
                      weight: FontWeight.w500,
                      color: RiseColors.positive))
            else if (badge.fraction != null)
              Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(RiseRadii.pill),
                    child: SizedBox(
                      height: 4,
                      child: ColoredBox(
                        color: RiseColors.surface2,
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: badge.fraction!.clamp(0.0, 1.0),
                          child: ColoredBox(
                              color: isNext
                                  ? RiseColors.waking
                                  : RiseColors.textDim),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text('${badge.progress} / ${badge.target}',
                      style: RiseText.mono(
                          size: 10, color: RiseColors.textFaint)),
                ],
              )
            else
              Text('next up',
                  style: RiseText.mono(
                      size: 10, color: RiseColors.textFaint)),
          ],
        ),
      ),
    );
  }

  static IconData _icon(String id) => switch (id) {
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
