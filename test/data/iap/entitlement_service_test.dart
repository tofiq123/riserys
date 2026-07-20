import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/iap/entitlement_service.dart';

void main() {
  group('UnlockedEntitlementService (graceful-degrade default)', () {
    test('reports premium unlocked synchronously and on the stream', () async {
      const service = UnlockedEntitlementService();
      expect(service.currentIsPremium, isTrue);
      expect(await service.isPremium().first, isTrue);
    });

    test('purchase and restore report premium (already unlocked)', () async {
      const service = UnlockedEntitlementService();
      expect(
          await service.purchase(const PremiumOffer(
              id: 'x', plan: PremiumPlan.monthly, priceString: r'$4.99')),
          isTrue);
      expect(await service.restorePurchases(), isTrue);
    });

    test('offers is empty (the paywall falls back to placeholder pricing)',
        () async {
      const service = UnlockedEntitlementService();
      expect(await service.offers(), isEmpty);
    });
  });

  group('FakeEntitlementService', () {
    test('defaults to locked and emits the initial state', () async {
      final service = FakeEntitlementService();
      addTearDown(service.dispose);
      expect(service.currentIsPremium, isFalse);
      expect(await service.isPremium().first, isFalse);
    });

    test('purchase flips premium and pushes to the stream', () async {
      final service = FakeEntitlementService();
      addTearDown(service.dispose);

      final seen = <bool>[];
      final sub = service.isPremium().listen(seen.add);
      addTearDown(sub.cancel);
      await Future<void>.delayed(Duration.zero);

      final ok = await service.purchase(const PremiumOffer(
          id: 'annual', plan: PremiumPlan.annual, priceString: r'$39.99'));
      await Future<void>.delayed(Duration.zero);

      expect(ok, isTrue);
      expect(service.currentIsPremium, isTrue);
      expect(seen, [false, true]);
    });

    test('a failed purchase leaves premium unchanged', () async {
      final service = FakeEntitlementService(purchaseSucceeds: false);
      addTearDown(service.dispose);

      final ok = await service.purchase(const PremiumOffer(
          id: 'm', plan: PremiumPlan.monthly, priceString: r'$4.99'));

      expect(ok, isFalse);
      expect(service.currentIsPremium, isFalse);
    });

    test('setPremium drives the stream (server-side entitlement change)',
        () async {
      final service = FakeEntitlementService(premium: true);
      addTearDown(service.dispose);
      expect(await service.restorePurchases(), isTrue);

      final seen = <bool>[];
      final sub = service.isPremium().listen(seen.add);
      addTearDown(sub.cancel);
      await Future<void>.delayed(Duration.zero);

      service.setPremium(false);
      await Future<void>.delayed(Duration.zero);
      expect(seen, [true, false]);
    });

    test('serves the offers it was constructed with', () async {
      final offers = [
        const PremiumOffer(
            id: 'annual', plan: PremiumPlan.annual, priceString: r'$39.99'),
      ];
      final service = FakeEntitlementService(offers: offers);
      addTearDown(service.dispose);
      expect(await service.offers(), same(offers));
    });
  });
}
