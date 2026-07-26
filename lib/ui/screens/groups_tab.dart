import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/group.dart';
import '../components/crew_add_sheet.dart';
import '../components/crew_group_card.dart';
import '../components/rise_error_card.dart';
import '../components/rise_skeleton.dart';
import '../state/group_providers.dart';
import '../theme/tokens.dart';
import 'group_detail_screen.dart';
import 'paywall_screen.dart';

/// The Groups strip of the Crew dashboard: horizontally scrolling group cards
/// (name, stacked member avatars, member count) plus dashed action cards —
/// "New group" always, and "Join a group" when you have none yet. Creating
/// and joining live in the shared add-people sheet, so the strip stays calm.
///
/// Kept as its own widget (same name as the old Groups sub-tab) so the Crew
/// screen embeds it and tests drive it standalone.
class GroupsTab extends ConsumerWidget {
  const GroupsTab({super.key});

  Future<void> _openSheet(
      BuildContext context, WidgetRef ref, CrewAddMode mode) async {
    final group = await showCrewAddSheet(
      context,
      initial: mode,
      onCrewLimit: () => openPaywall(context),
    );
    if (group != null && context.mounted) _open(context, group);
  }

  void _open(BuildContext context, Group g) {
    Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => GroupDetailScreen(group: g)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(myGroupsProvider);
    return SizedBox(
      height: kCrewGroupCardHeight + 8,
      child: groups.when(
        loading: () => ListView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          padding: const EdgeInsets.only(bottom: 8),
          children: const [
            RiseSkeleton(
                width: 150, height: kCrewGroupCardHeight, radius: RiseRadii.base),
            SizedBox(width: 10),
            RiseSkeleton(
                width: 150, height: kCrewGroupCardHeight, radius: RiseRadii.base),
          ],
        ),
        error: (_, __) => RiseErrorCard(
          message: 'Could not load your groups.',
          onRetry: () => ref.invalidate(myGroupsProvider),
        ),
        data: (list) => ListView.separated(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          padding: const EdgeInsets.only(bottom: 8),
          itemCount: list.length + (list.isEmpty ? 2 : 1),
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) {
            if (i < list.length) {
              return CrewGroupCard(
                group: list[i],
                onTap: () => _open(context, list[i]),
              );
            }
            if (i == list.length) {
              return CrewDashedCard(
                key: const Key('new-group-card'),
                icon: Icons.add,
                label: 'New group',
                onTap: () => _openSheet(context, ref, CrewAddMode.newGroup),
              );
            }
            return CrewDashedCard(
              key: const Key('join-group-card'),
              icon: Icons.tag,
              label: 'Join a group',
              onTap: () => _openSheet(context, ref, CrewAddMode.joinGroup),
            );
          },
        ),
      ),
    );
  }
}
