import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/clock_format.dart';
import '../../domain/feed_item.dart';
import '../state/feed_providers.dart';
import '../state/settings_providers.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'crew_avatar.dart';
import 'rise_card.dart';

/// "2h ago"-style relative time for feed items. Pure; a future [wokeAt]
/// (clock skew) degrades to "just now".
String crewRelativeTime(DateTime wokeAt, DateTime now) {
  final d = now.difference(wokeAt);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays == 1) return 'yesterday';
  return '${d.inDays}d ago';
}

/// One celebrated wake: avatar, "Ada woke on time", when, the streak it
/// landed (flame + mono numeral), and the emoji reaction row. Shared by the
/// Crew dashboard's inline "Cheer them on" section and the full Activity
/// screen so both stay pixel-identical. Reacting toggles through the existing
/// feed service and refreshes [crewFeedProvider].
class CrewFeedTile extends ConsumerWidget {
  const CrewFeedTile({super.key, required this.item});

  final FeedItem item;

  String get _who => item.isMe
      ? 'You'
      : (item.displayName.isNotEmpty ? item.displayName : '@${item.username}');

  String get _headline => '$_who ${item.onTime ? 'woke on time' : 'woke up'}';

  String _meta(bool use24h) {
    final local = item.wokeAt.toLocal();
    final time = formatClock(local.hour, local.minute, use24h: use24h);
    return '$time  ·  ${crewRelativeTime(item.wokeAt, DateTime.now())}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final use24h = ref.watch(currentSettingsProvider).use24HourTime;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: RiseCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CrewAvatar(
                    username: item.username,
                    colorHex: item.avatarColor,
                    size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_headline,
                          style: RiseText.body
                              .copyWith(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(_meta(use24h),
                          style: RiseText.caption
                              .copyWith(color: RiseColors.textDim)),
                    ],
                  ),
                ),
                if (item.streak >= 1) ...[
                  const SizedBox(width: 8),
                  _StreakFlame(id: item.id, streak: item.streak),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 2,
              children: [
                for (final emoji in kFeedReactionEmojis)
                  _ReactionChip(item: item, emoji: emoji),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The streak badge on a feed tile: a flame + the run in mono numerals.
class _StreakFlame extends StatelessWidget {
  const _StreakFlame({required this.id, required this.streak});

  final String id;
  final int streak;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: Key('feed-streak-$id'),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: RiseColors.accentSoft,
        borderRadius: BorderRadius.circular(RiseRadii.pill),
        border: Border.all(color: RiseColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🔥', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          Text('$streak',
              style: RiseText.mono(size: 13, weight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// One emoji in the reaction row: shows the crew tally and the signed-in
/// user's own toggle state; the visual chip is compact but the hit target is
/// padded to comfortable thumb size.
class _ReactionChip extends ConsumerWidget {
  const _ReactionChip({required this.item, required this.emoji});

  final FeedItem item;
  final String emoji;

  Future<void> _toggle(WidgetRef ref) async {
    final service = ref.read(feedServiceProvider);
    final reacted = item.reactionFor(emoji).reactedByMe;
    if (reacted) {
      await service.unreact(item.id, emoji);
    } else {
      await service.react(item.id, emoji);
    }
    ref.invalidate(crewFeedProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reaction = item.reactionFor(emoji);
    final mine = reaction.reactedByMe;
    return GestureDetector(
      key: Key('reaction-${item.id}-$emoji'),
      behavior: HitTestBehavior.opaque,
      onTap: () => unawaited(_toggle(ref)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: mine ? RiseColors.accentSoft : RiseColors.surface2,
            borderRadius: BorderRadius.circular(RiseRadii.pill),
            border: Border.all(
                color: mine ? RiseColors.primary : RiseColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 15)),
              if (reaction.count > 0) ...[
                const SizedBox(width: 6),
                Text('${reaction.count}',
                    style: RiseText.mono(
                        size: 12,
                        weight: FontWeight.w600,
                        color:
                            mine ? RiseColors.primary : RiseColors.textDim)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
