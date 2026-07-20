import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/crew_member.dart';
import '../../domain/crew_standing.dart';
import '../../domain/group.dart';
import '../../domain/wake_stats.dart';
import 'group_service.dart';

/// Production [GroupService]: groups + membership in Supabase, joined to
/// `profiles`/`stats`. Create/join go through the `create_group` /
/// `join_group_by_code` SECURITY DEFINER RPCs (see 0006_groups.sql); leave /
/// delete / rename / kick are RLS-gated table writes. Only constructed when
/// configured, and only off the alarm path.
///
/// NOTE: build-verified only (no live backend in CI). The real flow is exercised
/// by the two-account join/leaderboard smoke test in the Phase 15 setup guide.
class SupabaseGroupService implements GroupService {
  SupabaseGroupService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  static const _defaultAvatarColor = '#7C9CF4';

  final SupabaseClient _client;

  String? get _me => _client.auth.currentUser?.id;

  int _int(Object? v) => (v as num?)?.toInt() ?? 0;

  Group _group(Map<String, dynamic> r, String role) => Group(
        id: r['id'] as String,
        name: (r['name'] as String?) ?? '',
        inviteCode: (r['invite_code'] as String?) ?? '',
        ownerId: (r['owner_id'] as String?) ?? '',
        role: role,
      );

  /// create_group returns a single `groups` row; supabase decodes that as a Map
  /// (or a one-element List depending on the client). Normalise both.
  Map<String, dynamic>? _firstRow(dynamic res) {
    if (res is Map) return res.cast<String, dynamic>();
    if (res is List && res.isNotEmpty && res.first is Map) {
      return (res.first as Map).cast<String, dynamic>();
    }
    return null;
  }

  /// Maps a raw Postgres error to a user-facing line, surfacing our own
  /// `raise exception` messages where recognised, else [fallback].
  String _friendly(String raw, String fallback) {
    final m = raw.toLowerCase();
    if (m.contains('no group with that code')) return 'No group with that code.';
    if (m.contains('owner cannot leave')) {
      return "Owners can't leave — delete the group instead.";
    }
    if (m.contains('needs a name')) return 'A group needs a name.';
    return fallback;
  }

  @override
  Future<List<Group>> myGroups() async {
    final me = _me;
    if (me == null) return const [];
    try {
      final memRows = await _client
          .from('group_members')
          .select('group_id, role')
          .eq('user_id', me);
      final ids = <String>[for (final r in memRows) r['group_id'] as String];
      if (ids.isEmpty) return const [];
      final roleById = <String, String>{
        for (final r in memRows)
          r['group_id'] as String: (r['role'] as String?) ?? 'member',
      };
      final rows = await _client
          .from('groups')
          .select('id, name, owner_id, invite_code')
          .inFilter('id', ids);
      final groups = <Group>[
        for (final r in rows) _group(r, roleById[r['id']] ?? 'member'),
      ];
      return sortGroups(groups);
    } catch (_) {
      return const []; // best-effort; never throw into the list
    }
  }

  @override
  Future<Group> createGroup(String name) async {
    if (_me == null) throw const GroupException('Sign in to create a group.');
    final n = name.trim();
    if (n.isEmpty) throw const GroupException('A group needs a name.');
    try {
      final res = await _client.rpc('create_group', params: {'name': n});
      final row = _firstRow(res);
      if (row == null) throw const GroupException('Could not create the group.');
      return _group(row, 'owner');
    } on PostgrestException catch (e) {
      throw GroupException(_friendly(e.message, 'Could not create the group.'));
    }
  }

  @override
  Future<Group> joinByCode(String code) async {
    final me = _me;
    if (me == null) throw const GroupException('Sign in to join a group.');
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) throw const GroupException('Enter an invite code.');
    try {
      final gid = await _client
          .rpc('join_group_by_code', params: {'code': normalized});
      final id = gid as String?;
      if (id == null) throw const GroupException('No group with that code.');
      final rows = await _client
          .from('groups')
          .select('id, name, owner_id, invite_code')
          .eq('id', id)
          .limit(1);
      if (rows.isEmpty) throw const GroupException('Could not open the group.');
      final row = rows.first;
      return _group(row, row['owner_id'] == me ? 'owner' : 'member');
    } on PostgrestException catch (e) {
      throw GroupException(_friendly(e.message, 'Could not join. Check the code.'));
    }
  }

  @override
  Future<void> leaveGroup(String groupId) async {
    final me = _me;
    if (me == null) return;
    try {
      await _client
          .from('group_members')
          .delete()
          .eq('group_id', groupId)
          .eq('user_id', me);
    } on PostgrestException catch (e) {
      // The DB guard trigger blocks an owner from leaving.
      throw GroupException(_friendly(
          e.message, "Owners can't leave — delete the group instead."));
    }
  }

  @override
  Future<void> deleteGroup(String groupId) async {
    try {
      await _client.from('groups').delete().eq('id', groupId);
    } on PostgrestException catch (e) {
      throw GroupException(_friendly(e.message, 'Could not delete the group.'));
    }
  }

  @override
  Future<void> renameGroup(String groupId, String name) async {
    final n = name.trim();
    if (n.isEmpty) throw const GroupException('A group needs a name.');
    try {
      await _client.from('groups').update({'name': n}).eq('id', groupId);
    } on PostgrestException catch (e) {
      throw GroupException(_friendly(e.message, 'Could not rename the group.'));
    }
  }

  @override
  Future<void> removeMember(String groupId, String userId) async {
    try {
      await _client
          .from('group_members')
          .delete()
          .eq('group_id', groupId)
          .eq('user_id', userId);
    } on PostgrestException catch (e) {
      throw GroupException(_friendly(e.message, 'Could not remove them.'));
    }
  }

  @override
  Future<List<CrewMember>> members(String groupId) async {
    if (_me == null) return const [];
    try {
      final memRows = await _client
          .from('group_members')
          .select('user_id, role')
          .eq('group_id', groupId);
      final ids = <String>[for (final r in memRows) r['user_id'] as String];
      if (ids.isEmpty) return const [];
      final profiles = await _client
          .from('profiles')
          .select('id, username, display_name, avatar_color')
          .inFilter('id', ids);
      final byId = {for (final p in profiles) p['id'] as String: p};
      final out = <CrewMember>[];
      for (final id in ids) {
        final p = byId[id];
        if (p == null) continue; // profile not readable — skip
        out.add(CrewMember(
          id: id,
          username: (p['username'] as String?) ?? '',
          displayName: (p['display_name'] as String?) ?? '',
          avatarColor: (p['avatar_color'] as String?) ?? _defaultAvatarColor,
        ));
      }
      return out;
    } catch (_) {
      return const []; // best-effort
    }
  }

  @override
  Future<List<CrewStanding>> leaderboard(String groupId) async {
    final me = _me;
    if (me == null) return const [];
    try {
      final memRows = await _client
          .from('group_members')
          .select('user_id')
          .eq('group_id', groupId);
      final ids = <String>[for (final r in memRows) r['user_id'] as String];
      if (ids.isEmpty) return const [];

      final statRows = await _client
          .from('stats')
          .select('user_id, current_streak, best_streak, total_wakes, on_time')
          .inFilter('user_id', ids);
      final statsById = {for (final r in statRows) r['user_id'] as String: r};

      final profiles = await _client
          .from('profiles')
          .select('id, username, display_name, avatar_color')
          .inFilter('id', ids);
      final profById = {for (final p in profiles) p['id'] as String: p};

      final standings = <CrewStanding>[];
      for (final id in ids) {
        final p = profById[id];
        if (p == null) continue; // profile not readable — skip
        final s = statsById[id];
        standings.add(CrewStanding(
          id: id,
          username: (p['username'] as String?) ?? '',
          displayName: (p['display_name'] as String?) ?? '',
          avatarColor: (p['avatar_color'] as String?) ?? _defaultAvatarColor,
          stats: s == null
              ? WakeStats.empty
              : WakeStats(
                  currentStreak: _int(s['current_streak']),
                  bestStreak: _int(s['best_streak']),
                  totalWakes: _int(s['total_wakes']),
                  onTimeCount: _int(s['on_time']),
                ),
          isMe: id == me,
        ));
      }
      return rankStandings(standings);
    } catch (_) {
      return const []; // best-effort
    }
  }
}
