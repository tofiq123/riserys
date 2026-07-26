import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/ui/components/hero_card.dart';

void main() {
  testWidgets('renders eyebrow and child on the inverse ground', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: HeroCard(
          eyebrow: 'THIS MORNING',
          child: Text('2 of 4 up'),
        ),
      ),
    ));
    expect(find.text('THIS MORNING'), findsOneWidget);
    expect(find.text('2 of 4 up'), findsOneWidget);
  });

  testWidgets('HeroButton fires and disables', (t) async {
    var taps = 0;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HeroCard(
          child: HeroButton(label: 'Do it', onPressed: () => taps++),
        ),
      ),
    ));
    await t.tap(find.text('Do it'));
    expect(taps, 1);

    await t.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: HeroCard(child: HeroButton(label: 'Do it', onPressed: null)),
      ),
    ));
    await t.tap(find.text('Do it'));
    expect(taps, 1, reason: 'disabled button must not fire');
  });
}
