import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../components/crew_entrance.dart';
import '../components/crew_feed_tile.dart';
import '../components/crew_hero.dart';
import '../state/auth_providers.dart';
import '../state/feed_providers.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// The full crew Activity feed: every recent wake-up from you + your crew,
/// each cheerable with an emoji reaction. Warm and pro-social — it celebrates
/// wakes and never shames a miss. Reached from the Crew dashboard's "Cheer
/// them on" section. Signed out (or unconfigured) shows a gentle prompt; an
/// empty feed invites adding friends.
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
        scrolledUnderElevation: 0,
        centerTitle: false,
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
      loading: () => const Center(
        child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, __) => const _FeedEmpty(),
      data: (items) {
        if (items.isEmpty) return const _FeedEmpty();
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(crewFeedProvider),
          color: RiseColors.text,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(
                RiseSpacing.screen, 12, RiseSpacing.screen, 40),
            itemCount: items.length,
            itemBuilder: (_, i) => CrewEntrance(
              index: i,
              child: CrewFeedTile(item: items[i]),
            ),
          ),
        );
      },
    );
  }
}

class _FeedEmpty extends StatelessWidget {
  const _FeedEmpty();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: const [
        SizedBox(height: 64),
        CrewHero(
          icon: Icons.wb_sunny_outlined,
          title: 'No crew activity yet',
          body: 'Add friends to cheer each other on. Every on-time wake '
              'shows up here.',
        ),
      ],
    );
  }
}

class _FeedSignedOut extends StatelessWidget {
  const _FeedSignedOut();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: CrewHero(
          icon: Icons.wb_sunny_outlined,
          title: 'Cheer on your crew',
          body: "Sign in from the Profile tab to see your crew's wake-ups "
              'and cheer them on.',
        ),
      ),
    );
  }
}
