import 'dart:async';

import 'package:collection/collection.dart';

import '../../domain/crew_member.dart';
import '../../domain/crew_state.dart';

/// The friendship state machine, abstracted so the whole send/accept/decline/
/// cancel/remove flow is testable without a backend. Production is
/// `SupabaseCrewService`; tests use [FakeCrewService]; unconfigured/signed-out
/// uses [DisabledCrewService].
abstract interface class CrewService {
  /// Emits the current crew on listen and again after every change.
  Stream<CrewState> watch();

  CrewState get current;

  /// Re-fetches the crew from the backend and re-emits on [watch] — the
  /// pull-to-refresh path (there is no friendships Realtime, so a peer's
  /// accept/request only becomes visible via an explicit reload). Best-effort:
  /// never throws.
  Future<void> reload();

  /// Resolves a username to a [CrewMember] (to send a request), or null.
  Future<CrewMember?> findByUsername(String username);

  Future<void> sendRequest(String userId);
  Future<void> acceptRequest(String userId);   // accept an incoming request
  Future<void> declineRequest(String userId);  // decline an incoming request
  Future<void> cancelRequest(String userId);   // cancel my outgoing request
  Future<void> removeFriend(String userId);
}

/// The looked-up username matches no user.
class UserNotFoundException implements Exception {
  const UserNotFoundException();
  @override
  String toString() => 'UserNotFoundException';
}

/// A friend request could not be made (self-add, duplicate, already friends,
/// or no such pending request). [message] is user-facing.
class FriendshipException implements Exception {
  const FriendshipException(this.message);
  final String message;
  @override
  String toString() => 'FriendshipException: $message';
}

/// In-memory [CrewService] for unit/widget tests. [directory] is the pool
/// [findByUsername] can resolve; [initial] seeds the crew; [selfId] guards
/// self-adds.
class FakeCrewService implements CrewService {
  FakeCrewService({
    this.selfId = 'me',
    List<CrewMember> directory = const [],
    CrewState initial = CrewState.empty,
  })  : _directory = {for (final m in directory) m.id: m},
        _friends = [...initial.friends],
        _incoming = [...initial.incoming],
        _outgoing = [...initial.outgoing];

  final String selfId;
  final Map<String, CrewMember> _directory;
  final List<CrewMember> _friends;
  final List<CrewMember> _incoming;
  final List<CrewMember> _outgoing;

  final StreamController<CrewState> _controller =
      StreamController<CrewState>.broadcast();

  CrewState _snapshot() => CrewState(
        friends: List.unmodifiable(_friends),
        incoming: List.unmodifiable(_incoming),
        outgoing: List.unmodifiable(_outgoing),
      );

  @override
  CrewState get current => _snapshot();

  @override
  Stream<CrewState> watch() async* {
    yield _snapshot();
    yield* _controller.stream;
  }

  /// Reloads observed by tests (the in-memory state is already current).
  int reloads = 0;

  @override
  Future<void> reload() async {
    reloads++;
    _emit();
  }

  void _emit() => _controller.add(_snapshot());

  @override
  Future<CrewMember?> findByUsername(String username) async {
    final u = username.toLowerCase();
    return _directory.values
        .firstWhereOrNull((m) => m.username.toLowerCase() == u);
  }

  @override
  Future<void> sendRequest(String userId) async {
    if (userId == selfId) {
      throw const FriendshipException("You can't add yourself.");
    }
    if (_friends.any((m) => m.id == userId)) {
      throw const FriendshipException('Already in your crew.');
    }
    if (_outgoing.any((m) => m.id == userId)) {
      throw const FriendshipException('Request already sent.');
    }
    if (_incoming.any((m) => m.id == userId)) {
      throw const FriendshipException(
          'They already sent you a request — accept it.');
    }
    // By here the guards above have ruled out anyone already in a bucket, so
    // the member can only be resolved from the directory.
    final member = _directory[userId];
    if (member == null) throw const UserNotFoundException();
    _outgoing.add(member);
    _emit();
  }

  @override
  Future<void> acceptRequest(String userId) async {
    final member = _incoming.firstWhereOrNull((m) => m.id == userId);
    if (member == null) throw const FriendshipException('No such request.');
    _incoming.removeWhere((m) => m.id == userId);
    _friends.add(member);
    _emit();
  }

  @override
  Future<void> declineRequest(String userId) async {
    _incoming.removeWhere((m) => m.id == userId);
    _emit();
  }

  @override
  Future<void> cancelRequest(String userId) async {
    _outgoing.removeWhere((m) => m.id == userId);
    _emit();
  }

  @override
  Future<void> removeFriend(String userId) async {
    _friends.removeWhere((m) => m.id == userId);
    _emit();
  }

  /// Releases the stream controller. Call from a test `addTearDown`.
  Future<void> dispose() => _controller.close();
}

/// Used when unconfigured/signed-out: an empty crew, and every write throws.
class DisabledCrewService implements CrewService {
  const DisabledCrewService();

  @override
  CrewState get current => CrewState.empty;

  @override
  Stream<CrewState> watch() => Stream.value(CrewState.empty);

  @override
  Future<void> reload() async {}

  @override
  Future<CrewMember?> findByUsername(String username) async => null;

  @override
  Future<void> sendRequest(String userId) async =>
      throw StateError('crew not configured');

  @override
  Future<void> acceptRequest(String userId) async =>
      throw StateError('crew not configured');

  @override
  Future<void> declineRequest(String userId) async =>
      throw StateError('crew not configured');

  @override
  Future<void> cancelRequest(String userId) async =>
      throw StateError('crew not configured');

  @override
  Future<void> removeFriend(String userId) async =>
      throw StateError('crew not configured');
}
