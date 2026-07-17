import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/auth/auth_service.dart';
import 'package:rise/domain/rise_account.dart';
import 'package:rise/ui/state/auth_providers.dart';

void main() {
  test('unconfigured: authServiceProvider is DisabledAuthService and account is null', () async {
    // In `flutter test` no --dart-define is set, so SupabaseConfig.isConfigured is false.
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(authServiceProvider), isA<DisabledAuthService>());
    final value = await container.read(accountProvider.future);
    expect(value, isNull);
  });

  test('accountProvider streams the (overridden) auth service state machine', () async {
    final fake = FakeAuthService();
    addTearDown(fake.dispose);
    final container = ProviderContainer(overrides: [
      authServiceProvider.overrideWithValue(fake),
    ]);
    addTearDown(container.dispose);

    final emissions = <RiseAccount?>[];
    final sub = container.listen<AsyncValue<RiseAccount?>>(
      accountProvider,
      (_, next) {
        if (next.hasValue) emissions.add(next.value);
      },
      fireImmediately: true,
    );
    addTearDown(sub.close);

    await Future<void>.delayed(Duration.zero); // initial null
    await fake.signInWithGoogle();
    await Future<void>.delayed(Duration.zero);
    await fake.claimUsername('ada', displayName: 'Ada');
    await Future<void>.delayed(Duration.zero);
    await fake.signOut();
    await Future<void>.delayed(Duration.zero);

    expect(emissions.any((a) => a == null), isTrue, reason: 'starts signed out');
    expect(emissions.any((a) => a?.needsUsername == true), isTrue, reason: 'signed in, no username');
    expect(emissions.any((a) => a?.username == 'ada'), isTrue, reason: 'claimed');
    expect(emissions.last, isNull, reason: 'signed out at the end');
  });
}
