import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/ui/screens/wellbeing_checkin_screen.dart';

Future<void> _pump(WidgetTester t) async {
  t.view.physicalSize = const Size(1200, 5000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(const MaterialApp(home: WellbeingCheckinScreen()));
  await t.pump();
}

void main() {
  testWidgets('renders both PHQ-2 items and the disclaimer up front', (t) async {
    await _pump(t);
    expect(find.textContaining('little interest or pleasure'), findsOneWidget);
    expect(find.textContaining('down, depressed, or hopeless'), findsOneWidget);
    expect(find.textContaining('not a diagnosis or medical advice'),
        findsOneWidget);
  });

  testWidgets('submit stays inert until both questions are answered', (t) async {
    await _pump(t);
    await t.tap(find.byKey(const Key('phq-submit')));
    await t.pump();
    // Still on the questions — no result yet.
    expect(find.byKey(const Key('phq-done')), findsNothing);
    expect(find.byKey(const Key('phq-0-0')), findsOneWidget);
  });

  testWidgets('a total at/above the cut point routes to the care off-ramp',
      (t) async {
    await _pump(t);
    await t.tap(find.byKey(const Key('phq-0-3'))); // "Nearly every day" = 3
    await t.pump();
    await t.tap(find.byKey(const Key('phq-1-3'))); // 3 -> total 6
    await t.pump();
    await t.tap(find.byKey(const Key('phq-submit')));
    await t.pump();

    expect(find.textContaining('worth talking through with someone'),
        findsOneWidget);
    expect(find.text('Find a helpline near you'), findsOneWidget);
    expect(find.textContaining('findahelpline.com'), findsOneWidget);
    expect(find.textContaining('local doctor'), findsOneWidget);
    // The disclaimer is always present.
    expect(find.textContaining('not a diagnosis or medical advice'),
        findsOneWidget);
    // Never a diagnostic/label word.
    expect(find.textContaining('abnormal'), findsNothing);
    expect(find.textContaining('depression'), findsNothing);
  });

  testWidgets('a low total shows a kind message but still offers resources',
      (t) async {
    await _pump(t);
    await t.tap(find.byKey(const Key('phq-0-0'))); // "Not at all" = 0
    await t.pump();
    await t.tap(find.byKey(const Key('phq-1-0'))); // 0 -> total 0
    await t.pump();
    await t.tap(find.byKey(const Key('phq-submit')));
    await t.pump();

    expect(find.textContaining('good to hear'), findsOneWidget);
    // The off-ramp is never gated — resources appear regardless of score.
    expect(find.text('Find a helpline near you'), findsOneWidget);
    expect(find.textContaining('not a diagnosis or medical advice'),
        findsOneWidget);
  });

  testWidgets('the result can be retaken, clearing prior answers', (t) async {
    await _pump(t);
    await t.tap(find.byKey(const Key('phq-0-1')));
    await t.pump();
    await t.tap(find.byKey(const Key('phq-1-1')));
    await t.pump();
    await t.tap(find.byKey(const Key('phq-submit')));
    await t.pump();
    expect(find.byKey(const Key('phq-done')), findsOneWidget);

    await t.tap(find.text('Take it again'));
    await t.pump();
    // Back on the questions with a fresh (unselected) form.
    expect(find.byKey(const Key('phq-submit')), findsOneWidget);
    expect(find.byKey(const Key('phq-done')), findsNothing);
  });
}
