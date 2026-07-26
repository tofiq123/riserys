import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/supabase_config.dart';
import '../../domain/rise_account.dart';
import 'auth_service.dart';
import 'profile_cache.dart';

/// Synchronous account priming from the locally restored Supabase session.
/// `Supabase.initialize()` restores the session before runApp, so by the time
/// this service is constructed the session truth is already known:
///
/// - no session → primed with `null`: the very first emission says signed out,
///   and the sign-in UI may render without any flash risk;
/// - session + cached profile for that user → primed with the cached account:
///   the first emission is the full signed-in account (username included), so
///   neither the sign-in hero nor the username-claim gate can flash;
/// - session but no usable cache → NOT primed: nothing is emitted until the
///   live profile fetch resolves, keeping consumers in a loading state (they
///   render a neutral skeleton — never "signed out", never the claim gate).
@visibleForTesting
({RiseAccount? account, bool primed}) primeFromSession(
    User? user, ProfileCache? cache) {
  if (user == null) return (account: null, primed: true);
  final cached = cache?.read(user.id);
  if (cached != null) return (account: cached, primed: true);
  return (account: null, primed: false);
}

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
    ProfileCache? cache,
  })  : _client = client ?? Supabase.instance.client,
        _serverClientId = serverClientId ?? SupabaseConfig.googleServerClientId,
        _cache = cache {
    // Prime from the locally restored session BEFORE subscribing, so the first
    // account() emission never guesses "signed out" while a session exists
    // (see primeFromSession). The onAuthStateChange listener below then
    // refreshes/refutes that with the live profiles row and drives every later
    // change (sign-in/out, token refresh).
    final primed = primeFromSession(_client.auth.currentSession?.user, _cache);
    _current = primed.account;
    _primed = primed.primed;
    _authSub = _client.auth.onAuthStateChange.listen((state) async {
      // Auth events process concurrently (the handler awaits a network
      // fetch): a slow tokenRefreshed fetch must never overwrite the result
      // of a newer signedOut. Only the latest event may apply its result.
      final seq = ++_authSeq;
      final user = state.session?.user;
      final acct = user == null ? null : await _accountForUser(user);
      if (seq != _authSeq) return; // superseded by a newer auth event
      if (user == null) {
        // Signed out (locally or remotely revoked): the cached profile must
        // not resurrect this account on the next launch. Best-effort.
        try {
          await _cache?.clear();
        } catch (_) {}
      }
      _primed = true;
      _current = acct;
      _accounts.add(acct);
    });
  }

  static const _defaultAvatarColor = '#7C9CF4';

  final SupabaseClient _client;
  final String _serverClientId;
  final ProfileCache? _cache;

  final StreamController<RiseAccount?> _accounts =
      StreamController<RiseAccount?>.broadcast();
  StreamSubscription<AuthState>? _authSub;
  Future<void>? _googleInit;
  RiseAccount? _current;

  /// Monotonic auth-event counter; see the onAuthStateChange handler.
  int _authSeq = 0;

  /// Whether [_current] reflects known truth. False only in the narrow
  /// "session restored but profile not yet fetched and not cached" window —
  /// there account() emits nothing, so providers stay in a loading state
  /// instead of wrongly reporting signed-out.
  bool _primed = true;

  @override
  RiseAccount? get current => _current;

  @override
  Stream<RiseAccount?> account() async* {
    if (_primed) yield _current;
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

    final account = RiseAccount(
      id: user.id,
      username: profile?['username'] as String?,
      displayName: (profile?['display_name'] as String?) ?? googleName ?? '',
      avatarColor:
          (profile?['avatar_color'] as String?) ?? _defaultAvatarColor,
      email: user.email,
    );
    // Persist confirmed profile knowledge (including a confirmed missing row)
    // so the next launch primes instantly. Never cache a failed fetch — that
    // would freeze a guess — and never for a session that ended while the
    // fetch was in flight (a sign-out just cleared this cache; a stale write
    // here would resurrect the account). Best-effort throughout.
    if (!fetchFailed && _client.auth.currentUser?.id == user.id) {
      try {
        await _cache?.write(account);
      } catch (_) {}
    }
    return account;
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
    // Also cleared by the signedOut auth event; doing it here too covers a
    // sign-out that never emits (e.g. the app is killed mid-call).
    try {
      await _cache?.clear();
    } catch (_) {}
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
