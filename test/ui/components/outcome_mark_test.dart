import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/wake_rhythm.dart';
import 'package:rise/ui/components/outcome_mark.dart';
import 'package:rise/ui/theme/tokens.dart';

void main() {
  Widget host(Widget child) =>
      MaterialApp(home: Scaffold(body: Center(child: child)));

  test('every outcome has a distinct, non-empty, non-judgemental label', () {
    final labels = [
      for (final o in RhythmOutcome.values) outcomeLabel(o),
    ];
    expect(labels.toSet(), hasLength(RhythmOutcome.values.length));
    for (final l in labels) {
      expect(l, isNotEmpty);
      expect(l, isNot(contains('!')));
      expect(l.toLowerCase(), isNot(contains('fail')));
    }
  });

  test('late never wears the danger colour — a late morning is not a failure',
      () {
    expect(outcomeColor(RhythmOutcome.late), isNot(RiseColors.danger));
    expect(outcomeColor(RhythmOutcome.late), RiseColors.text);
  });

  test('on time and slept through are different tokens', () {
    expect(outcomeColor(RhythmOutcome.onTime),
        isNot(outcomeColor(RhythmOutcome.sleptThrough)));
  });

  testWidgets('renders a mark for every outcome without throwing',
      (t) async {
    for (final o in RhythmOutcome.values) {
      await t.pumpWidget(host(OutcomeMark(o)));
      expect(find.byType(CustomPaint), findsWidgets, reason: '$o');
    }
  });

  testWidgets('renders square marks and freeze pips', (t) async {
    await t.pumpWidget(host(const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutcomeMark(RhythmOutcome.late, square: true, freeze: true),
        OutcomeMark(RhythmOutcome.sleptThrough, square: true),
      ],
    )));
    expect(t.takeException(), isNull);
    expect(find.byType(OutcomeMark), findsNWidgets(2));
  });

  testWidgets('the legend labels every mark it shows', (t) async {
    await t.pumpWidget(host(const SizedBox(width: 320, child: OutcomeLegend())));
    for (final o in [
      RhythmOutcome.onTime,
      RhythmOutcome.late,
      RhythmOutcome.sleptThrough,
      RhythmOutcome.restDay,
    ]) {
      expect(find.text(outcomeLabel(o)), findsOneWidget);
    }
  });

  testWidgets('a narrowed legend explains only the marks that are present',
      (t) async {
    await t.pumpWidget(host(const SizedBox(
      width: 320,
      child: OutcomeLegend(
          outcomes: [RhythmOutcome.onTime, RhythmOutcome.late]),
    )));
    expect(find.text(outcomeLabel(RhythmOutcome.onTime)), findsOneWidget);
    expect(find.text(outcomeLabel(RhythmOutcome.sleptThrough)), findsNothing);
  });
}
