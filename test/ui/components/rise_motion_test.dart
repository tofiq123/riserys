import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/ui/components/rise_motion.dart';

void main() {
  testWidgets('RisePressable dispatches taps', (t) async {
    var taps = 0;
    await t.pumpWidget(MaterialApp(
      home: Center(
        child: RisePressable(
          onTap: () => taps++,
          child: const SizedBox(width: 80, height: 40, child: Text('tap')),
        ),
      ),
    ));
    await t.tap(find.text('tap'));
    await t.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('RisePressable with null onTap does not throw on tap',
      (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Center(
        child: RisePressable(
          onTap: null,
          child: SizedBox(width: 80, height: 40, child: Text('tap')),
        ),
      ),
    ));
    await t.tap(find.text('tap'));
    await t.pumpAndSettle();
  });

  testWidgets('RiseFade crossfades between keyed states', (t) async {
    Widget host(Widget child) =>
        MaterialApp(home: Center(child: RiseFade(child: child)));

    await t.pumpWidget(host(RiseFade.keyed('a', const Text('first'))));
    await t.pumpAndSettle();
    expect(find.text('first'), findsOneWidget);

    await t.pumpWidget(host(RiseFade.keyed('b', const Text('second'))));
    await t.pump(const Duration(milliseconds: 120));
    // Mid-transition both exist; after settling only the new one remains.
    await t.pumpAndSettle();
    expect(find.text('second'), findsOneWidget);
    expect(find.text('first'), findsNothing);
  });

  testWidgets('RiseFade is instant under reduced motion', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Center(child: RiseFade(child: Text('now'))),
      ),
    ));
    expect(find.text('now'), findsOneWidget);
    await t.pumpAndSettle();
  });
}
