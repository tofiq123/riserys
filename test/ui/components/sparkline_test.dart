import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/ui/components/sparkline.dart';

Future<void> _pump(WidgetTester t, Widget child) async {
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 200, child: child)),
    ),
  ));
}

void main() {
  testWidgets('renders a multi-point sparkline without error', (t) async {
    await _pump(t, const Sparkline(values: [10, 40, 30, 80, 60]));
    expect(find.byType(Sparkline), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('renders a single value (baseline dot) without error', (t) async {
    await _pump(t, const Sparkline(values: [50]));
    expect(find.byType(Sparkline), findsOneWidget);
  });

  testWidgets('renders empty values without error', (t) async {
    await _pump(t, const Sparkline(values: []));
    expect(find.byType(Sparkline), findsOneWidget);
  });
}
