import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/iap/entitlement_service.dart';
import 'package:rise/ui/state/entitlement_providers.dart';

void main() {
  test(
      'unconfigured: entitlementServiceProvider is UnlockedEntitlementService '
      'and isPremium is true (everything unlocked)', () async {
    // In `flutter test` no --dart-define is set, so RevenueCatConfig.isConfigured
    // is false — this is the graceful-degrade default the whole phase relies on.
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(entitlementServiceProvider),
        isA<UnlockedEntitlementService>());
    expect(await container.read(isPremiumProvider.future), isTrue);
  });

  test('isPremiumProvider streams the (overridden) entitlement service',
      () async {
    final fake = FakeEntitlementService();
    addTearDown(fake.dispose);
    final container = ProviderContainer(overrides: [
      entitlementServiceProvider.overrideWithValue(fake),
    ]);
    addTearDown(container.dispose);

    final seen = <bool>[];
    final sub = container.listen<AsyncValue<bool>>(
      isPremiumProvider,
      (_, next) {
        if (next.hasValue) seen.add(next.value!);
      },
      fireImmediately: true,
    );
    addTearDown(sub.close);

    await Future<void>.delayed(Duration.zero); // initial: locked
    fake.setPremium(true);
    await Future<void>.delayed(Duration.zero);

    expect(seen.first, isFalse, reason: 'starts locked');
    expect(seen.last, isTrue, reason: 'unlocked after purchase');
  });
}
