import 'dart:async';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/supabase_config.dart';
import '../../domain/rise_account.dart';
import 'auth_service.dart';

/// Production [AuthService]: Google native sign-in → Supabase session, backed by
/// a `profiles` row. Only constructed when the backend is configured, and only
/// off the alarm path — a total backend outage disables social, never the alarm.
///
/// NOTE: build-verified only (no live backend/Google in CI). The logic here is
/// exercised end-to-end by the user's device smoke test in the setup guide.
class SupabaseAuthService implements AuthService {
  SupabaseAuthService({
    SupabaseClient? client,
    String? serverClientId,
  })  : _client = client ?? Supabase.instance.client,
        _serverClientId = serverClientId ?? SupabaseConfig.googleServerClientId {
    // onAuthStateChange emits the initial session on subscribe, so this primes
    // _current and drives every later change (sign-in/out, token refresh).
    _authSub = _client.auth.onAuthStateChange.listen((state) async {
      final user = state.session?.user;
      final acct = user == null ? null : await _accountForUser(user);
      _current = acct;
      _accounts.add(acct);
    });
  }

  static const _defaultAvatarColor = '#7C9CF4';

  final SupabaseClient _client;
  final String _serverClientId;

  final StreamController<RiseAccount?> _accounts =
      StreamController<RiseAccount?>.broadcast();
  StreamSubscription<AuthState>? _authSub;
  Future<void>? _googleInit;
  RiseAccount? _current;

  @override
  RiseAccount? get current => _current;

  @override
  Stream<RiseAccount?> account() async* {
    yield _current;
    yield* _accounts.stream;
  }

  Future<void> _ensureGoogleInitialized() async {
    // Cache the init Future so initialize() runs at most once, but drop the
    // cache if it fails so a transient failure (e.g. Play Services briefly
    // unavailable) doesn't permanently wedge sign-in — the next attempt retries.
    try {
      await (_googleInit ??=
          GoogleSignIn.instance.initialize(serverClientId: _serverClientId));
    } catch (_) {
      _googleInit = null;
      rethrow;
    }
  }

  /// Builds a [RiseAccount] for [user], reading the optional `profiles` row.
  /// A missing row means the username has not been claimed yet (needsUsername).
  Future<RiseAccount> _accountForUser(User user) async {
    // Best-effort throughout: this runs inside the onAuthStateChange listener,
    // so it must never throw (an uncaught error there escapes an unawaited
    // callback). It also runs on EVERY auth event — sign-in, token refresh,
    // resume — so a transient profile-fetch failure must never be mistaken for
    // "no profile row": doing so would wrongly route an already-claimed user
    // to the username-claim gate whenever a refetch blips.
    final googleName = (user.userMetadata?['full_name'] ??
        user.userMetadata?['name']) as String?;

    Map<String, dynamic>? profile;
    var fetchFailed = false;
    // A couple of quick retries absorb a network blip on a just-woken phone or
    // a token that's still settling right after sign-in.
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        profile = await _client
            .from('profiles')
            .select()
            .eq('id', user.id)
            .maybeSingle();
        fetchFailed = false;
        break;
      } catch (_) {
        fetchFailed = true;
        if (attempt < 2) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }
      }
    }

    // If every attempt failed we do NOT know whether a profile exists. Never
    // downgrade a known account to needs-username on a failed fetch: keep the
    // last-known account for this user (which carries the claimed username) so
    // the claim gate can't flash on a transient refetch. A confirmed empty
    // result (fetch succeeded, no row) still correctly routes to the gate.
    if (fetchFailed) {
      final prior = _current;
      if (prior != null && prior.id == user.id) return prior;
    }

    return RiseAccount(
      id: user.id,
      username: profile?['username'] as String?,
      displayName: (profile?['display_name'] as String?) ?? googleName ?? '',
      avatarColor:
          (profile?['avatar_color'] as String?) ?? _defaultAvatarColor,
      email: user.email,
    );
  }

  @override
  Future<void> signInWithGoogle() async {
    await _ensureGoogleInitialized();
    final googleAccount = await GoogleSignIn.instance.authenticate();
    final idToken = googleAccount.authentication.idToken;
    if (idToken == null) {
      throw const AuthException('Google sign-in returned no ID token.');
    }
    await _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
    );
    // onAuthStateChange fires signedIn → _accounts emits the new account.
  }

  @override
  Future<bool> isUsernameAvailable(String username) async {
    // A SECURITY DEFINER RPC (see supabase/migrations/0001_profiles.sql): under
    // own-row-only RLS a direct select can't see other users' rows, so the RPC
    // checks existence server-side and returns just a boolean. The DB `unique`
    // constraint remains the real guard against a check→insert race.
    final result = await _client.rpc(
      'username_available',
      params: {'name': username.toLowerCase()},
    );
    return result == true;
  }

  @override
  Future<void> claimUsername(String username,
      {required String displayName}) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('claimUsername called while signed out');
    }
    try {
      await _client.from('profiles').insert({
        'id': user.id,
        'username': username.toLowerCase(),
        'display_name': displayName,
      });
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        // unique_violation: the username (or this user's row) already exists.
        throw UsernameTakenException(username);
      }
      rethrow;
    }
    // No auth-state change fires for a DB insert, so refresh manually.
    _current = await _accountForUser(user);
    _accounts.add(_current);
  }

  @override
  Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // best-effort; the Supabase sign-out below is what actually matters
    }
    await _client.auth.signOut();
  }

  @override
  Future<void> deleteAccount() async {
    await _client.functions.invoke('delete-account');
    await signOut();
  }

  /// Cancels the auth subscription and closes the stream. Wire to the
  /// provider's `ref.onDispose`.
  Future<void> dispose() async {
    await _authSub?.cancel();
    await _accounts.close();
  }
}
