import 'dart:async';

import '../../domain/rise_account.dart';

/// The account/session state machine, abstracted so the whole
/// sign-in → claim-username → sign-out/delete flow is testable without a live
/// backend. Production is `SupabaseAuthService`; tests use [FakeAuthService];
/// when no backend is configured the app uses [DisabledAuthService].
abstract interface class AuthService {
  /// Emits the current account on listen and again on every auth-state change.
  /// `null` means signed out.
  Stream<RiseAccount?> account();

  /// The last known account synchronously, or `null` when signed out.
  RiseAccount? get current;

  Future<void> signInWithGoogle();

  /// Best-effort availability check for UX only; the DB `unique` constraint is
  /// the real guard (a lost race surfaces as [UsernameTakenException] on claim).
  Future<bool> isUsernameAvailable(String username);

  /// Claims [username] for the signed-in account. Throws
  /// [UsernameTakenException] if it is already taken.
  Future<void> claimUsername(String username, {required String displayName});

  Future<void> signOut();

  Future<void> deleteAccount();
}

/// Thrown by [AuthService.claimUsername] when the username is already taken.
class UsernameTakenException implements Exception {
  const UsernameTakenException(this.username);
  final String username;
  @override
  String toString() => 'UsernameTakenException: "$username" is already taken';
}

/// In-memory [AuthService] for unit/widget tests. Sign-in produces an account
/// with no username (as a first-time Google sign-in would, before a profile row
/// exists); [claimUsername] sets it. [signOut]/[deleteAccount] return to signed
/// out. Availability is checked against an in-memory taken-set (case-insensitive).
class FakeAuthService implements AuthService {
  FakeAuthService({
    Set<String> takenUsernames = const {},
    RiseAccount? initialAccount,
    this.newAccountId = 'fake-uid',
    this.newAccountDisplayName = 'New User',
    this.newAccountEmail = 'new.user@example.com',
    this.newAccountAvatarColor = '#7C9CF4',
  })  : _taken = {for (final u in takenUsernames) u.toLowerCase()},
        _current = initialAccount;

  final Set<String> _taken;
  final String newAccountId;
  final String newAccountDisplayName;
  final String newAccountEmail;
  final String newAccountAvatarColor;

  final StreamController<RiseAccount?> _controller =
      StreamController<RiseAccount?>.broadcast();
  RiseAccount? _current;

  @override
  RiseAccount? get current => _current;

  @override
  Stream<RiseAccount?> account() async* {
    yield _current;
    yield* _controller.stream;
  }

  void _emit(RiseAccount? account) {
    _current = account;
    _controller.add(account);
  }

  @override
  Future<void> signInWithGoogle() async {
    _emit(RiseAccount(
      id: newAccountId,
      username: null, // no profile row yet → routes to the claim screen
      displayName: newAccountDisplayName,
      avatarColor: newAccountAvatarColor,
      email: newAccountEmail,
    ));
  }

  @override
  Future<bool> isUsernameAvailable(String username) async =>
      !_taken.contains(username.toLowerCase());

  @override
  Future<void> claimUsername(String username,
      {required String displayName}) async {
    final account = _current;
    if (account == null) {
      throw StateError('claimUsername called while signed out');
    }
    final normalized = username.toLowerCase();
    if (_taken.contains(normalized)) {
      throw UsernameTakenException(username);
    }
    _taken.add(normalized);
    _emit(account.copyWith(username: normalized, displayName: displayName));
  }

  @override
  Future<void> signOut() async => _emit(null);

  @override
  Future<void> deleteAccount() async {
    final claimed = _current?.username;
    if (claimed != null) _taken.remove(claimed);
    _emit(null);
  }

  /// Releases the stream controller. Call from a test `addTearDown`.
  Future<void> dispose() => _controller.close();
}

/// Used when no backend is configured: no account, and every backend-requiring
/// action throws. The UI hides sign-in when disabled, so these throwers are
/// never reached in normal use — they fail loudly if they somehow are.
class DisabledAuthService implements AuthService {
  const DisabledAuthService();

  @override
  RiseAccount? get current => null;

  @override
  Stream<RiseAccount?> account() => Stream.value(null);

  @override
  Future<void> signInWithGoogle() async =>
      throw StateError('auth not configured');

  @override
  Future<bool> isUsernameAvailable(String username) async => false;

  @override
  Future<void> claimUsername(String username,
          {required String displayName}) async =>
      throw StateError('auth not configured');

  @override
  Future<void> signOut() async {}

  @override
  Future<void> deleteAccount() async =>
      throw StateError('auth not configured');
}
