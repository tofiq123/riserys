import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/auth/profile_cache.dart';
import 'package:rise/data/auth/supabase_auth_service.dart';
import 'package:rise/domain/rise_account.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A minimal restored-session user, as `currentSession?.user` would hand back
/// right after `Supabase.initialize()` restored a local session.
User _user(String id) => User(
      id: id,
      appMetadata: const {},
      userMetadata: const {'full_name': 'Ada Lovelace'},
      aud: 'authenticated',
      createdAt: '2026-01-01T00:00:00Z',
      email: 'ada@example.com',
    );

void main() {
  const cached = RiseAccount(
    id: 'u1',
    username: 'ada',
    displayName: 'Ada L.',
    avatarColor: '#AABBCC',
    email: 'ada@example.com',
  );

  Future<ProfileCache> cacheWith(RiseAccount? account) async {
    SharedPreferences.setMockInitialValues(const {});
    final cache = ProfileCache(await SharedPreferences.getInstance());
    if (account != null) await cache.write(account);
    return cache;
  }

  group('primeFromSession', () {
    test('no restored session primes to signed out (emit null immediately)',
        () async {
      final result = primeFromSession(null, await cacheWith(cached));
      expect(result.primed, isTrue);
      expect(result.account, isNull);
    });

    test('restored session + matching cache primes to the cached account',
        () async {
      final result = primeFromSession(_user('u1'), await cacheWith(cached));
      expect(result.primed, isTrue);
      expect(result.account, cached);
    });

    test('restored session with no cache stays unprimed (loading, not signed out)',
        () async {
      final result = primeFromSession(_user('u1'), await cacheWith(null));
      expect(result.primed, isFalse);
      expect(result.account, isNull);
    });

    test('cache for a different user is ignored — unprimed', () async {
      final result = primeFromSession(_user('u9'), await cacheWith(cached));
      expect(result.primed, isFalse);
      expect(result.account, isNull);
    });

    test('restored session with no cache object at all stays unprimed', () {
      final result = primeFromSession(_user('u1'), null);
      expect(result.primed, isFalse);
      expect(result.account, isNull);
    });
  });
}
