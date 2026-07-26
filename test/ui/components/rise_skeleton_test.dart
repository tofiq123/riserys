import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/ui/components/rise_skeleton.dart';

void main() {
  testWidgets('renders at the requested size', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Center(child: RiseSkeleton(width: 120, height: 14)),
    ));
    await t.pump();
    final size = t.getSize(find.byType(RiseSkeleton));
    expect(size.width, 120);
    expect(size.height, 14);
  });

  testWidgets('circle variant is square at the given size', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Center(child: RiseSkeletonCircle(size: 52)),
    ));
    await t.pump();
    expect(t.getSize(find.byType(RiseSkeletonCircle)), const Size(52, 52));
  });

  testWidgets('pulses while visible, and settles when removed', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Center(child: RiseSkeleton(width: 80, height: 12)),
    ));
    // A repeating pulse never settles — pumpAndSettle would hang. Frames
    // advance without error instead.
    await t.pump(const Duration(milliseconds: 500));
    await t.pump(const Duration(milliseconds: 500));
    // Removing the skeleton must tear the animation down cleanly.
    await t.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await t.pumpAndSettle();
  });

  testWidgets('reduced motion renders statically (settles immediately)',
      (t) async {
    await t.pumpWidget(const MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Center(child: RiseSkeleton(width: 80, height: 12)),
      ),
    ));
    // Static: no repeating animation scheduled, so this settles.
    await t.pumpAndSettle();
    expect(find.byType(RiseSkeleton), findsOneWidget);
  });
}
