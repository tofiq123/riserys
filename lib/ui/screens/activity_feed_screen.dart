import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/clock_format.dart';
import '../../domain/feed_item.dart';
import '../components/rise_card.dart';
import '../state/auth_providers.dart';
import '../state/feed_providers.dart';
import '../state/settings_providers.dart';
import '../theme/avatar_color.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// The crew Activity feed: recent wake-ups from you + your crew, each cheerable
/// with an emoji reaction. Warm and pro-social — it celebrates wakes and never
/// shames a miss. Reached from the Crew tab. Signed out (or unconfigured) shows
/// a gentle prompt; an empty feed invites adding friends.
class ActivityFeedScreen extends ConsumerWidget {
  const ActivityFeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(accountProvider).value != null;
    return Scaffold(
      backgroundColor: RiseColors.appBg,
      appBar: AppBar(
        backgroundColor: RiseColors.appBg,
        elevation: 0,
        title: Text('Activity', style: RiseText.title),
        iconTheme: IconThemeData(color: RiseColors.text),
      ),
      body: SafeArea(
        top: false,
        child: signedIn ? const _FeedBody() : const _FeedSignedOut(),
      ),
    );
  }
}

class _FeedBody extends ConsumerWidget {
  const _FeedBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(crewFeedProvider);
    return feed.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const _FeedEmpty(),
      data: (items) {
        if (items.isEmpty) return const _FeedEmpty();
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(crewFeedProvider),
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(
                RiseSpacing.screen, 12, RiseSpacing.screen, 40),
            itemCount: items.length,
            itemBuilder: (_, i) => _FeedTile(item: items[i]),
          ),
        );
      },
    );
  }
}

class _FeedTile extends ConsumerWidget {
  const _FeedTile({required this.item});

  final FeedItem item;

  String get _who => item.isMe
      ? 'You'
      : (item.displayName.isNotEmpty ? item.displayName : '@${item.username}');

  String get _headline =>
      '$_who ${item.onTime ? 'woke on time' : 'woke up'}';

  String _meta(bool use24h) {
    final time = formatClock(
        item.wokeAt.toLocal().hour, item.wokeAt.toLocal().minute,
        use24h: use24h);
    final parts = <String>[
      if (item.streak >= 1) '${item.streak}-day streak',
      time,
    ];
    return parts.join('  ·  ');
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
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: avatarColorFromHex(item.avatarColor),
                      shape: BoxShape.circle),
                  child: Text(
                    (item.username.isNotEmpty ? item.username : '?')
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
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
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
                      color: mine ? RiseColors.primary : RiseColors.textDim)),
            ],
          ],
        ),
      ),
    );
  }
}

class _FeedEmpty extends StatelessWidget {
  const _FeedEmpty();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 80),
        Icon(Icons.wb_sunny_outlined,
            size: 44, color: RiseColors.textFaint),
        const SizedBox(height: 16),
        Text('No crew activity yet', textAlign: TextAlign.center,
            style: RiseText.title),
        const SizedBox(height: 8),
        Text('Add friends to cheer each other on. Every on-time wake shows up here.',
            textAlign: TextAlign.center,
            style: RiseText.body.copyWith(color: RiseColors.textDim)),
      ],
    );
  }
}

class _FeedSignedOut extends StatelessWidget {
  const _FeedSignedOut();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wb_sunny_outlined,
              size: 44, color: RiseColors.textFaint),
          const SizedBox(height: 16),
          Text('Cheer on your crew', style: RiseText.title),
          const SizedBox(height: 8),
          Text(
              'Sign in from the Profile tab to see your crew\'s wake-ups and cheer them on.',
              textAlign: TextAlign.center,
              style: RiseText.body.copyWith(color: RiseColors.textDim)),
        ],
      ),
    );
  }
}
