import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/iap/entitlement_service.dart';
import 'package:rise/ui/screens/paywall_screen.dart';
import 'package:rise/ui/state/entitlement_providers.dart';

const _offers = [
  PremiumOffer(id: 'ann', plan: PremiumPlan.annual, priceString: r'$29.99'),
  PremiumOffer(id: 'mon', plan: PremiumPlan.monthly, priceString: r'$3.99'),
  PremiumOffer(id: 'life', plan: PremiumPlan.lifetime, priceString: r'$59.99'),
];

Future<void> _pump(WidgetTester t, FakeEntitlementService fake) async {
  t.view.physicalSize = const Size(2400, 9000);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [entitlementServiceProvider.overrideWithValue(fake)],
    child: const MaterialApp(home: PaywallScreen()),
  ));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('not premium: shows plans with real store prices', (t) async {
    final fake = FakeEntitlementService(offers: _offers);
    addTearDown(fake.dispose);
    await _pump(t, fake);

    expect(find.text('Rise Premium'), findsOneWidget);
    // Real offer prices win over the placeholders.
    expect(find.text(r'$29.99'), findsOneWidget);
    expect(find.text(r'$3.99'), findsOneWidget);
    expect(find.text(r'$59.99'), findsOneWidget);
    expect(find.byKey(const Key('paywall-subscribe')), findsOneWidget);
    expect(find.byKey(const Key('paywall-restore')), findsOneWidget);
  });

  testWidgets('unconfigured (no offers): shows placeholder pricing', (t) async {
    final fake = FakeEntitlementService(); // locked, no offers
    addTearDown(fake.dispose);
    await _pump(t, fake);

    expect(find.text(r'$39.99'), findsOneWidget); // annual placeholder
    expect(find.text(r'$4.99'), findsOneWidget); // monthly placeholder
    expect(find.text(r'$79.99'), findsOneWidget); // lifetime placeholder
  });

  testWidgets('subscribe purchases the selected plan (annual by default)',
      (t) async {
    final fake = FakeEntitlementService(offers: _offers);
    addTearDown(fake.dispose);
    await _pump(t, fake);

    await t.tap(find.byKey(const Key('paywall-subscribe')));
    await t.pumpAndSettle();

    expect(fake.currentIsPremium, isTrue);
    // The screen flips to the premium state after the entitlement change.
    expect(find.text('You\'re on Rise Premium'), findsOneWidget);
  });

  testWidgets('selecting monthly then subscribing buys monthly', (t) async {
    final fake = FakeEntitlementService(offers: _offers);
    addTearDown(fake.dispose);
    await _pump(t, fake);

    await t.tap(find.byKey(const Key('paywall-plan-monthly')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('paywall-subscribe')));
    await t.pumpAndSettle();

    expect(fake.currentIsPremium, isTrue);
  });

  testWidgets('already premium: shows the unlocked state, no plan tiles',
      (t) async {
    final fake = FakeEntitlementService(premium: true, offers: _offers);
    addTearDown(fake.dispose);
    await _pump(t, fake);

    expect(find.text('You\'re on Rise Premium'), findsOneWidget);
    expect(find.byKey(const Key('paywall-plan-annual')), findsNothing);
    expect(find.byKey(const Key('paywall-restore')), findsOneWidget);
  });

  testWidgets('restore with no purchase reports nothing found', (t) async {
    final fake = FakeEntitlementService(offers: _offers); // locked
    addTearDown(fake.dispose);
    await _pump(t, fake);

    await t.tap(find.byKey(const Key('paywall-restore')));
    await t.pumpAndSettle();

    expect(find.text('No previous purchase found for this account.'),
        findsOneWidget);
  });
}
