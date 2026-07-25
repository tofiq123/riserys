import 'package:collection/collection.dart';

import '../../domain/crew_member.dart';
import '../../domain/crew_standing.dart';
import '../../domain/group.dart';
import '../../domain/group_challenge.dart';

/// Groups: create / join-by-code / leave / delete / rename / kick, plus roster
/// and per-group leaderboard reads. Production is `SupabaseGroupService`; tests
/// use [FakeGroupService]; unconfigured/signed-out uses [DisabledGroupService].
///
/// Fetch-on-open (no Realtime): providers re-fetch on invalidate, mirroring the
/// crew leaderboard.
abstract interface class GroupService {
  /// Groups the signed-in user belongs to, display-sorted.
  Future<List<Group>> myGroups();

  /// Creates a group owned by the signed-in user (via the `create_group` RPC).
  Future<Group> createGroup(String name);

  /// Joins a group by its invite [code] (via the `join_group_by_code` RPC).
  Future<Group> joinByCode(String code);

  /// Leaves a group. Owners cannot leave — they [deleteGroup] instead.
  Future<void> leaveGroup(String groupId);

  /// Disbands a group the signed-in user owns (cascade removes members).
  Future<void> deleteGroup(String groupId);

  /// Renames a group the signed-in user owns.
  Future<void> renameGroup(String groupId, String name);

  /// Owner-only: removes [userId] from the group.
  Future<void> removeMember(String groupId, String userId);

  /// The group's roster (profiles).
  Future<List<CrewMember>> members(String groupId);

  /// The group's leaderboard (members ranked by wake consistency).
  Future<List<CrewStanding>> leaderboard(String groupId);

  /// The group's active streak race, or null if none is running (see
  /// 0013_group_challenges.sql). Any member may read it.
  Future<GroupChallenge?> activeChallenge(String groupId);

  /// Owner-only: starts a streak race for the group and returns it. Throws
  /// [GroupException] if a race is already running.
  Future<GroupChallenge> startChallenge(String groupId);

  /// Owner-only: ends the running streak race.
  Future<void> endChallenge(String challengeId);
}

/// A group action could not be completed; [message] is user-facing.
class GroupException implements Exception {
  const GroupException(this.message);
  final String message;
  @override
  String toString() => 'GroupException: $message';
}

/// In-memory [GroupService] for unit/widget tests. Seed with [groups],
/// [members], and [standings]; [joinCode]/[joinTarget] control [joinByCode].
class FakeGroupService implements GroupService {
  FakeGroupService({
    this.selfId = 'me',
    List<Group> groups = const [],
    Map<String, List<CrewMember>> members = const {},
    Map<String, List<CrewStanding>> standings = const {},
    Map<String, GroupChallenge> challenges = const {},
    this.joinCode = 'RISE42',
    this.joinTarget,
  })  : _groups = [...groups],
        _members = {for (final e in members.entries) e.key: [...e.value]},
        _standings = {for (final e in standings.entries) e.key: [...e.value]},
        _challenges = {...challenges};

  final String selfId;
  final List<Group> _groups;
  final Map<String, List<CrewMember>> _members;
  final Map<String, List<CrewStanding>> _standings;
  final Map<String, GroupChallenge> _challenges; // groupId -> active race

  /// The code [joinByCode] accepts (case-insensitive); anything else throws.
  final String joinCode;

  /// The group returned/added on a successful join. Defaults to a stub.
  final Group? joinTarget;

  int _seq = 0;

  @override
  Future<List<Group>> myGroups() async => sortGroups(_groups);

  @override
  Future<Group> createGroup(String name) async {
    final n = name.trim();
    if (n.isEmpty) throw const GroupException('A group needs a name.');
    final g = Group(
      id: 'g${_seq++}',
      name: n,
      inviteCode: 'CODE$_seq',
      ownerId: selfId,
      role: 'owner',
      memberCount: 1,
    );
    _groups.add(g);
    return g;
  }

  @override
  Future<Group> joinByCode(String code) async {
    if (code.trim().toUpperCase() != joinCode.toUpperCase()) {
      throw const GroupException('No group with that code.');
    }
    final g = joinTarget ??
        const Group(
          id: 'joined',
          name: 'Joined group',
          inviteCode: 'RISE42',
          ownerId: 'other',
          role: 'member',
          memberCount: 2,
        );
    if (!_groups.any((x) => x.id == g.id)) _groups.add(g);
    return g;
  }

  @override
  Future<void> leaveGroup(String groupId) async {
    final g = _groups.where((x) => x.id == groupId).firstOrNull;
    if (g != null && g.isOwner) {
      throw const GroupException(
          "Owners can't leave — delete the group instead.");
    }
    _groups.removeWhere((x) => x.id == groupId);
  }

  @override
  Future<void> deleteGroup(String groupId) async {
    _groups.removeWhere((x) => x.id == groupId);
    _members.remove(groupId);
    _standings.remove(groupId);
  }

  @override
  Future<void> renameGroup(String groupId, String name) async {
    final n = name.trim();
    if (n.isEmpty) throw const GroupException('A group needs a name.');
    final i = _groups.indexWhere((x) => x.id == groupId);
    if (i >= 0) _groups[i] = _groups[i].copyWith(name: n);
  }

  @override
  Future<void> removeMember(String groupId, String userId) async {
    _members[groupId]?.removeWhere((m) => m.id == userId);
    _standings[groupId]?.removeWhere((s) => s.id == userId);
  }

  @override
  Future<List<CrewMember>> members(String groupId) async =>
      List.unmodifiable(_members[groupId] ?? const []);

  @override
  Future<List<CrewStanding>> leaderboard(String groupId) async =>
      rankStandings(_standings[groupId] ?? const []);

  @override
  Future<GroupChallenge?> activeChallenge(String groupId) async =>
      _challenges[groupId];

  @override
  Future<GroupChallenge> startChallenge(String groupId) async {
    if (_challenges.containsKey(groupId)) {
      throw const GroupException('A streak race is already running.');
    }
    final c = GroupChallenge(
        id: 'ch${_seq++}', groupId: groupId, startedAt: DateTime.now());
    _challenges[groupId] = c;
    return c;
  }

  @override
  Future<void> endChallenge(String challengeId) async =>
      _challenges.removeWhere((_, c) => c.id == challengeId);
}

/// Used when unconfigured/signed-out: no groups, reads empty, every write
/// throws. The UI gates group actions behind a signed-in account, so these
/// throws are never reached in normal use.
class DisabledGroupService implements GroupService {
  const DisabledGroupService();

  @override
  Future<List<Group>> myGroups() async => const [];

  @override
  Future<Group> createGroup(String name) async =>
      throw StateError('groups not configured');

  @override
  Future<Group> joinByCode(String code) async =>
      throw StateError('groups not configured');

  @override
  Future<void> leaveGroup(String groupId) async =>
      throw StateError('groups not configured');

  @override
  Future<void> deleteGroup(String groupId) async =>
      throw StateError('groups not configured');

  @override
  Future<void> renameGroup(String groupId, String name) async =>
      throw StateError('groups not configured');

  @override
  Future<void> removeMember(String groupId, String userId) async =>
      throw StateError('groups not configured');

  @override
  Future<List<CrewMember>> members(String groupId) async => const [];

  @override
  Future<List<CrewStanding>> leaderboard(String groupId) async => const [];

  @override
  Future<GroupChallenge?> activeChallenge(String groupId) async => null;

  @override
  Future<GroupChallenge> startChallenge(String groupId) async =>
      throw StateError('groups not configured');

  @override
  Future<void> endChallenge(String challengeId) async =>
      throw StateError('groups not configured');
}
