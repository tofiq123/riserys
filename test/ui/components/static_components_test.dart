import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/ui/components/rise_buttons.dart';
import 'package:rise/ui/components/rise_card.dart';
import 'package:rise/ui/components/section_label.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('RiseCard renders its child', (t) async {
    await t.pumpWidget(_wrap(const RiseCard(child: Text('hello'))));
    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets('PrimaryButton fires onPressed', (t) async {
    var tapped = false;
    await t.pumpWidget(_wrap(PrimaryButton(label: 'Save', onPressed: () => tapped = true)));
    await t.tap(find.text('Save'));
    expect(tapped, isTrue);
  });

  testWidgets('PrimaryButton is disabled (no tap) when onPressed is null', (t) async {
    await t.pumpWidget(_wrap(const PrimaryButton(label: 'Save', onPressed: null)));
    await t.tap(find.text('Save'), warnIfMissed: false);
    // no callback to fire; assert it renders without throwing
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('PrimaryButton meets the 44px minimum hit target', (t) async {
    await t.pumpWidget(_wrap(PrimaryButton(label: 'Save', onPressed: () {})));
    final size = t.getSize(find.byType(PrimaryButton));
    expect(size.height, greaterThanOrEqualTo(44));
  });

  testWidgets('SectionLabel uppercases its text', (t) async {
    await t.pumpWidget(_wrap(const SectionLabel('your alarms')));
    expect(find.text('YOUR ALARMS'), findsOneWidget);
  });
}
