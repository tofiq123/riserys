import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/crew_member.dart';
import '../../domain/crew_state.dart';
import 'crew_service.dart';

/// Production [CrewService]: friend relationships in the Supabase `friendships`
/// table, joined to `profiles`. Only constructed when configured, and only off
/// the alarm path. Re-loads after each mutation (Realtime arrives in 5c).
///
/// NOTE: build-verified only (no live backend in CI). The real flow is
/// exercised by the two-account smoke test in the 5b setup guide.
class SupabaseCrewService implements CrewService {
  SupabaseCrewService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client {
    // onAuthStateChange emits the initial session on subscribe, so this primes
    // the crew and reloads on every sign-in/out.
    _authSub = _client.auth.onAuthStateChange.listen((state) {
      if (state.session?.user == null) {
        _current = CrewState.empty;
        _controller.add(_current);
      } else {
        unawaited(_reload());
      }
    });
  }

  static const _defaultAvatarColor = '#7C9CF4';

  final SupabaseClient _client;
  final StreamController<CrewState> _controller =
      StreamController<CrewState>.broadcast();
  StreamSubscription<AuthState>? _authSub;
  CrewState _current = CrewState.empty;

  @override
  CrewState get current => _current;

  @override
  Stream<CrewState> watch() async* {
    yield _current;
    yield* _controller.stream;
  }

  Future<void> _reload() async {
    try {
      _current = await _fetch();
    } catch (_) {
      _current = CrewState.empty; // best-effort; never throw into the stream
    }
    _controller.add(_current);
  }

  CrewMember _memberFromProfile(Map<String, dynamic> p) => CrewMember(
        id: p['id'] as String,
        username: (p['username'] as String?) ?? '',
        displayName: (p['display_name'] as String?) ?? '',
        avatarColor: (p['avatar_color'] as String?) ?? _defaultAvatarColor,
      );

  Future<CrewState> _fetch() async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return CrewState.empty;

    final rows = await _client
        .from('friendships')
        .select('requester, addressee, status')
        .or('requester.eq.$me,addressee.eq.$me');

    final friendIds = <String>[];
    final incomingIds = <String>[];
    final outgoingIds = <String>[];
    for (final row in rows) {
      final requester = row['requester'] as String;
      final addressee = row['addressee'] as String;
      final status = row['status'] as String;
      final other = requester == me ? addressee : requester;
      if (status == 'accepted') {
        friendIds.add(other);
      } else if (addressee == me) {
        incomingIds.add(other); // pending, they asked me
      } else {
        outgoingIds.add(other); // pending, I asked them
      }
    }

    final allIds = <String>{...friendIds, ...incomingIds, ...outgoingIds}.toList();
    final profiles = allIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : await _client
            .from('profiles')
            .select('id, username, display_name, avatar_color')
            .inFilter('id', allIds);

    final byId = {
      for (final p in profiles) p['id'] as String: _memberFromProfile(p),
    };

    List<CrewMember> membersFor(List<String> ids) =>
        ids.map((id) => byId[id]).whereType<CrewMember>().toList();

    return CrewState(
      friends: membersFor(friendIds),
      incoming: membersFor(incomingIds),
      outgoing: membersFor(outgoingIds),
    );
  }

  @override
  Future<CrewMember?> findByUsername(String username) async {
    final rows = await _client.rpc(
      'find_user_by_username',
      params: {'name': username.toLowerCase()},
    );
    final list = rows as List;
    if (list.isEmpty) return null;
    final member = _memberFromProfile(list.first as Map<String, dynamic>);
    if (member.id == _client.auth.currentUser?.id) return null; // not yourself
    return member;
  }

  @override
  Future<void> sendRequest(String userId) async {
    final me = _client.auth.currentUser!.id;
    try {
      await _client.from('friendships').insert({
        'requester': me,
        'addressee': userId,
        'status': 'pending',
      });
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw const FriendshipException(
            'You already have a pending or accepted request with them.');
      }
      rethrow;
    }
    await _reload();
  }

  @override
  Future<void> acceptRequest(String userId) async {
    final me = _client.auth.currentUser!.id;
    await _client
        .from('friendships')
        .update({'status': 'accepted'})
        .eq('requester', userId)
        .eq('addressee', me);
    await _reload();
  }

  @override
  Future<void> declineRequest(String userId) async {
    final me = _client.auth.currentUser!.id;
    await _client
        .from('friendships')
        .delete()
        .eq('requester', userId)
        .eq('addressee', me);
    await _reload();
  }

  @override
  Future<void> cancelRequest(String userId) async {
    final me = _client.auth.currentUser!.id;
    await _client
        .from('friendships')
        .delete()
        .eq('requester', me)
        .eq('addressee', userId);
    await _reload();
  }

  @override
  Future<void> removeFriend(String userId) async {
    final me = _client.auth.currentUser!.id;
    // The accepted row may be in either direction.
    await _client.from('friendships').delete().or(
        'and(requester.eq.$me,addressee.eq.$userId),'
        'and(requester.eq.$userId,addressee.eq.$me)');
    await _reload();
  }

  /// Cancels the auth subscription and closes the stream. Wire to the
  /// provider's `ref.onDispose`.
  Future<void> dispose() async {
    await _authSub?.cancel();
    await _controller.close();
  }
}
