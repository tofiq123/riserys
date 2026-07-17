import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/auth/auth_service.dart';
import 'package:rise/ui/components/rise_buttons.dart';
import 'package:rise/ui/screens/username_claim_screen.dart';
import 'package:rise/ui/state/auth_providers.dart';

Future<FakeAuthService> _pump(WidgetTester tester,
    {Set<String> taken = const {}, VoidCallback? onClaimed}) async {
  final fake = FakeAuthService(takenUsernames: taken);
  await fake.signInWithGoogle(); // claim requires a signed-in account
  addTearDown(fake.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [authServiceProvider.overrideWithValue(fake)],
    child: MaterialApp(
      home: Scaffold(body: UsernameClaimScreen(onClaimed: onClaimed)),
    ),
  ));
  await tester.pumpAndSettle();
  return fake;
}

PrimaryButton _claimButton(WidgetTester tester) =>
    tester.widget<PrimaryButton>(find.byType(PrimaryButton));

void main() {
  testWidgets('Claim is disabled until a valid, available username is entered',
      (tester) async {
    await _pump(tester);
    expect(_claimButton(tester).onPressed, isNull, reason: 'nothing typed');

    await tester.enterText(find.byKey(const Key('username-field')), 'ab'); // too short
    await tester.pumpAndSettle();
    expect(_claimButton(tester).onPressed, isNull, reason: 'invalid format');

    await tester.enterText(find.byKey(const Key('username-field')), 'ada');
    await tester.pumpAndSettle();
    expect(_claimButton(tester).onPressed, isNotNull, reason: 'valid + available');
  });

  testWidgets('claiming a valid username calls the service', (tester) async {
    var claimed = false;
    final fake = await _pump(tester, onClaimed: () => claimed = true);

    await tester.enterText(find.byKey(const Key('username-field')), 'ada');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PrimaryButton));
    await tester.pumpAndSettle();

    expect(fake.current!.username, 'ada');
    expect(claimed, isTrue);
  });

  testWidgets('a taken username reports taken and keeps Claim disabled',
      (tester) async {
    await _pump(tester, taken: {'taken'});
    await tester.enterText(find.byKey(const Key('username-field')), 'taken');
    await tester.pumpAndSettle();

    expect(find.textContaining('taken'), findsWidgets);
    expect(_claimButton(tester).onPressed, isNull);
  });

  testWidgets('Sign out calls the service', (tester) async {
    final fake = await _pump(tester);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(fake.current, isNull);
  });
}
