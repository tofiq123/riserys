import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/auth/profile_cache.dart';
import 'package:rise/domain/rise_account.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const account = RiseAccount(
    id: 'u1',
    username: 'ada',
    displayName: 'Ada L.',
    avatarColor: '#7C9CF4',
    email: 'ada@example.com',
  );

  Future<ProfileCache> cache() async {
    SharedPreferences.setMockInitialValues(const {});
    return ProfileCache(await SharedPreferences.getInstance());
  }

  test('write then read round-trips the account', () async {
    final c = await cache();
    await c.write(account);
    expect(c.read('u1'), account);
  });

  test('read for a different user id returns null', () async {
    final c = await cache();
    await c.write(account);
    expect(c.read('someone-else'), isNull);
  });

  test('read with nothing stored returns null', () async {
    final c = await cache();
    expect(c.read('u1'), isNull);
  });

  test('clear removes the cached profile', () async {
    final c = await cache();
    await c.write(account);
    await c.clear();
    expect(c.read('u1'), isNull);
  });

  test('corrupt stored JSON reads as null, never throws', () async {
    SharedPreferences.setMockInitialValues({'cachedProfile': '{not json'});
    final c = ProfileCache(await SharedPreferences.getInstance());
    expect(c.read('u1'), isNull);
  });

  test('an unclaimed (null username) account round-trips', () async {
    final c = await cache();
    await c.write(const RiseAccount(
        id: 'u2', displayName: 'New', avatarColor: '#7C9CF4'));
    final got = c.read('u2');
    expect(got, isNotNull);
    expect(got!.needsUsername, isTrue);
    expect(got.email, isNull);
  });
}
