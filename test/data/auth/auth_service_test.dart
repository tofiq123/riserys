import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/auth/auth_service.dart';
import 'package:rise/domain/rise_account.dart';

void main() {
  group('FakeAuthService', () {
    test('starts signed out', () {
      final svc = FakeAuthService();
      addTearDown(svc.dispose);
      expect(svc.current, isNull);
    });

    test('signInWithGoogle produces an account that needs a username', () async {
      final svc = FakeAuthService();
      addTearDown(svc.dispose);
      await svc.signInWithGoogle();
      expect(svc.current, isNotNull);
      expect(svc.current!.needsUsername, isTrue, reason: 'no profile row yet');
      expect(svc.current!.email, isNotEmpty);
    });

    test('claimUsername sets username + displayName on the current account', () async {
      final svc = FakeAuthService();
      addTearDown(svc.dispose);
      await svc.signInWithGoogle();
      await svc.claimUsername('ada', displayName: 'Ada L.');
      expect(svc.current!.username, 'ada');
      expect(svc.current!.displayName, 'Ada L.');
      expect(svc.current!.needsUsername, isFalse);
    });

    test('isUsernameAvailable is false for a taken name (case-insensitive), true otherwise', () async {
      final svc = FakeAuthService(takenUsernames: {'taken'});
      addTearDown(svc.dispose);
      expect(await svc.isUsernameAvailable('taken'), isFalse);
      expect(await svc.isUsernameAvailable('TAKEN'), isFalse);
      expect(await svc.isUsernameAvailable('free'), isTrue);
    });

    test('claimUsername throws UsernameTakenException for a taken name and leaves the account unclaimed', () async {
      final svc = FakeAuthService(takenUsernames: {'taken'});
      addTearDown(svc.dispose);
      await svc.signInWithGoogle();
      await expectLater(
        svc.claimUsername('taken', displayName: 'X'),
        throwsA(isA<UsernameTakenException>()),
      );
      expect(svc.current!.needsUsername, isTrue, reason: 'claim failed, still no username');
    });

    test('a claimed username becomes unavailable to others', () async {
      final svc = FakeAuthService();
      addTearDown(svc.dispose);
      await svc.signInWithGoogle();
      await svc.claimUsername('ada', displayName: 'Ada');
      expect(await svc.isUsernameAvailable('ada'), isFalse);
    });

    test('signOut returns to signed out', () async {
      final svc = FakeAuthService();
      addTearDown(svc.dispose);
      await svc.signInWithGoogle();
      await svc.signOut();
      expect(svc.current, isNull);
    });

    test('deleteAccount returns to signed out', () async {
      final svc = FakeAuthService();
      addTearDown(svc.dispose);
      await svc.signInWithGoogle();
      await svc.claimUsername('ada', displayName: 'Ada');
      await svc.deleteAccount();
      expect(svc.current, isNull);
    });

    test('account() emits null, then signed-in-no-username, then claimed, then null', () async {
      final svc = FakeAuthService();
      addTearDown(svc.dispose);
      final expectation = expectLater(
        svc.account(),
        emitsInOrder([
          isNull,
          predicate<RiseAccount?>((a) => a != null && a.needsUsername),
          predicate<RiseAccount?>((a) => a?.username == 'ada'),
          isNull,
        ]),
      );
      await Future<void>.delayed(Duration.zero); // let the listener subscribe
      await svc.signInWithGoogle();
      await svc.claimUsername('ada', displayName: 'Ada');
      await svc.signOut();
      await expectation;
    });
  });

  group('DisabledAuthService', () {
    const svc = DisabledAuthService();

    test('current is null and account() emits null', () async {
      expect(svc.current, isNull);
      expect(await svc.account().first, isNull);
    });

    test('signInWithGoogle throws (backend not configured)', () {
      expect(svc.signInWithGoogle(), throwsA(isA<StateError>()));
    });

    test('signOut is a harmless no-op', () async {
      await svc.signOut(); // must not throw
    });
  });
}
