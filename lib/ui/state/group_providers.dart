import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/supabase_config.dart';
import '../../data/group/group_service.dart';
import '../../data/group/supabase_group_service.dart';
import '../../domain/crew_member.dart';
import '../../domain/crew_standing.dart';
import '../../domain/group.dart';
import '../../domain/group_challenge.dart';
import 'auth_providers.dart';

/// The app's [GroupService]. Configured → a real [SupabaseGroupService];
/// otherwise a [DisabledGroupService] (no groups, no writes). Tests override
/// this with a `FakeGroupService`.
final groupServiceProvider = Provider<GroupService>((ref) {
  if (!SupabaseConfig.isConfigured) {
    return const DisabledGroupService();
  }
  return SupabaseGroupService();
});

/// The signed-in user's groups. Cached for the session (warmed at shell
/// level); refresh with `ref.invalidate(myGroupsProvider)` after create/join/
/// leave, on pull-to-refresh, or on tab open. Keyed to the signed-in account
/// id so cached groups never leak across a sign-out/sign-in swap. Empty while
/// loading, unconfigured, or signed out — the app is usable regardless.
final myGroupsProvider = FutureProvider<List<Group>>((ref) {
  ref.watch(accountProvider.select((a) => a.value?.id));
  return ref.watch(groupServiceProvider).myGroups();
});

/// A group's roster (profiles), keyed by group id.
final groupMembersProvider =
    FutureProvider.family<List<CrewMember>, String>((ref, groupId) {
  return ref.watch(groupServiceProvider).members(groupId);
});

/// A group's leaderboard (members ranked by wake consistency), keyed by group
/// id. Reuses the crew standing/stats model.
final groupLeaderboardProvider =
    FutureProvider.family<List<CrewStanding>, String>((ref, groupId) {
  return ref.watch(groupServiceProvider).leaderboard(groupId);
});

/// A group's active streak race, or null if none is running. Fetch-on-open;
/// refresh with `ref.invalidate(groupChallengeProvider(groupId))`. Keyed by
/// group id.
final groupChallengeProvider =
    FutureProvider.family<GroupChallenge?, String>((ref, groupId) {
  return ref.watch(groupServiceProvider).activeChallenge(groupId);
});
