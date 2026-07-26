import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/wake_event.dart';
import 'package:rise/domain/wake_rhythm.dart';
import 'package:rise/ui/components/consistency_grid.dart';
import 'package:rise/ui/components/outcome_mark.dart';

void main() {
  // Sunday, so the five weeks fill exactly 35 cells.
  final now = DateTime(2026, 7, 26, 12);

  WakeEvent ev(DateTime day, {int? after}) {
    final ring = DateTime(day.year, day.month, day.day, 6, 45);
    return WakeEvent(
      id: day.day + day.month * 100,
      alarmId: 1,
      scheduledAt: ring,
      firstRingAt: ring,
      dismissedAt: after == null ? null : ring.add(Duration(minutes: after)),
      onTime: after != null && after <= kOnTimeGrace.inMinutes,
    );
  }

  Future<void> pump(WidgetTester t, Widget child) async {
    t.view.physicalSize = const Size(1125, 2400);
    t.view.devicePixelRatio = 3.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Padding(padding: const EdgeInsets.all(20), child: child))));
    await t.pumpAndSettle();
  }

  testWidgets('lays five Monday-first weeks out as a calendar', (t) async {
    final days = buildRhythmWeeks([], now, weeks: 5);
    expect(days, hasLength(35));
    await pump(t, ConsistencyGrid(days: days));
    expect(t.takeException(), isNull);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('the tally line counts what happened', (t) async {
    final days = buildRhythmWeeks(
      [
        ev(DateTime(2026, 7, 20), after: 3), // on time
        ev(DateTime(2026, 7, 21), after: 3), // on time
        ev(DateTime(2026, 7, 22), after: 45), // late
        ev(DateTime(2026, 7, 23), after: null), // slept through
        ev(DateTime(2026, 7, 24), after: 3), // excused below
      ],
      now,
      weeks: 5,
      excusedDays: {DateTime(2026, 7, 24)},
    );
    await pump(t, ConsistencyGrid(days: days));
    expect(find.text('2 on time · 1 late · 1 slept through · 1 rest day'),
        findsOneWidget);
  });

  testWidgets('an untouched month reads as a sentence, not a blank', (t) async {
    await pump(t, ConsistencyGrid(days: buildRhythmWeeks([], now, weeks: 5)));
    expect(find.text('Nothing logged in these weeks yet.'), findsOneWidget);
  });

  testWidgets('an empty list degrades to the same sentence', (t) async {
    await pump(t, const ConsistencyGrid(days: []));
    expect(find.text('Nothing logged in these weeks yet.'), findsOneWidget);
  });

  testWidgets('the legend explains only the marks the month contains',
      (t) async {
    final days = buildRhythmWeeks(
        [ev(DateTime(2026, 7, 20), after: 3)], now, weeks: 5);
    await pump(t, ConsistencyGrid(days: days));
    expect(find.text(outcomeLabel(RhythmOutcome.onTime)), findsOneWidget);
    expect(find.text(outcomeLabel(RhythmOutcome.sleptThrough)), findsNothing);
  });

  testWidgets('a mid-week today gives a short final row without breaking',
      (t) async {
    final days =
        buildRhythmWeeks([], DateTime(2026, 7, 22, 12), weeks: 5); // Wednesday
    expect(days, hasLength(31));
    await pump(t, ConsistencyGrid(days: days));
    expect(t.takeException(), isNull);
  });

  testWidgets('the tally can be suppressed for a compact placement', (t) async {
    await pump(
        t,
        ConsistencyGrid(
            days: buildRhythmWeeks([], now, weeks: 5), showTally: false));
    expect(find.text('Nothing logged in these weeks yet.'), findsNothing);
  });
}
