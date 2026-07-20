import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/iap/entitlement_service.dart';
import 'package:rise/domain/premium_feature.dart';
import 'package:rise/ui/state/entitlement_providers.dart';

void main() {
  test('PremiumGate(true) unlocks every feature', () {
    const gate = PremiumGate(true);
    for (final f in PremiumFeature.values) {
      expect(gate.canUse(f), isTrue);
    }
  });

  test('PremiumGate(false) allows free features, blocks premium', () {
    const gate = PremiumGate(false);
    expect(gate.canUse(PremiumFeature.reliableAlarm), isTrue);
    expect(gate.canUse(PremiumFeature.phq2Checkin), isTrue);
    expect(gate.canUse(PremiumFeature.pvtMission), isTrue);
    expect(gate.canUse(PremiumFeature.advancedMissions), isFalse);
    expect(gate.canUse(PremiumFeature.monthlyYearlyStats), isFalse);
  });

  test(
      'unconfigured: premiumGateProvider unlocks everything (graceful degrade)',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(isPremiumProvider.future);

    final gate = container.read(premiumGateProvider);
    expect(gate.isPremium, isTrue);
    expect(gate.canUse(PremiumFeature.advancedMissions), isTrue);
  });

  test('configured-but-locked (fake): premium is gated, care stays free',
      () async {
    final fake = FakeEntitlementService(premium: false);
    addTearDown(fake.dispose);
    final container = ProviderContainer(overrides: [
      entitlementServiceProvider.overrideWithValue(fake),
    ]);
    addTearDown(container.dispose);
    await container.read(isPremiumProvider.future);

    final gate = container.read(premiumGateProvider);
    expect(gate.isPremium, isFalse);
    expect(gate.canUse(PremiumFeature.advancedMissions), isFalse);
    expect(gate.canUse(PremiumFeature.smartWakeCheck), isFalse);
    expect(gate.canUse(PremiumFeature.phq2Checkin), isTrue);
    expect(gate.canUse(PremiumFeature.pvtMission), isTrue);
  });
}
