import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/wake_event.dart';
import 'package:rise/domain/wake_rhythm.dart';
import 'package:rise/ui/components/outcome_mark.dart';
import 'package:rise/ui/components/wake_rhythm_chart.dart';

void main() {
  final now = DateTime(2026, 7, 26, 12);

  WakeEvent ev(int day, {int ringH = 6, int ringM = 45, int? after}) {
    final ring = DateTime(2026, 7, day, ringH, ringM);
    return WakeEvent(
      id: day,
      alarmId: 1,
      scheduledAt: ring,
      firstRingAt: ring,
      dismissedAt: after == null ? null : ring.add(Duration(minutes: after)),
      onTime: after != null && after <= kOnTimeGrace.inMinutes,
    );
  }

  List<RhythmDay> fortnight() => buildRhythm(
        [
          for (var d = 13; d <= 26; d++)
            ev(d, after: d == 18 ? 55 : (d == 21 ? null : 4)),
        ],
        now,
        days: 14,
      );

  Future<void> pump(WidgetTester t, Widget child, {bool wide = true}) async {
    t.view.physicalSize = Size(wide ? 1125 : 960, 2400);
    t.view.devicePixelRatio = 3.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Padding(
                padding: const EdgeInsets.all(20), child: child))));
    await t.pumpAndSettle();
  }

  testWidgets('renders a chart for a fortnight of mornings', (t) async {
    await pump(t, WakeRhythmChart(days: fortnight()));
    expect(find.byType(CustomPaint), findsWidgets);
    expect(t.takeException(), isNull);
  });

  testWidgets('the legend explains only the outcomes actually present',
      (t) async {
    await pump(t, WakeRhythmChart(days: fortnight()));
    // The fortnight has on-time, late and slept-through — but no rest day.
    expect(find.text(outcomeLabel(RhythmOutcome.onTime)), findsOneWidget);
    expect(find.text(outcomeLabel(RhythmOutcome.late)), findsOneWidget);
    expect(find.text(outcomeLabel(RhythmOutcome.sleptThrough)), findsOneWidget);
    expect(find.text(outcomeLabel(RhythmOutcome.restDay)), findsNothing);
  });

  testWidgets('an empty fortnight says what appears, never an empty axis',
      (t) async {
    await pump(t, WakeRhythmChart(days: buildRhythm([], now, days: 14)));
    expect(find.text('No mornings to chart yet'), findsOneWidget);
    expect(find.byKey(const Key('rhythm-list-toggle')), findsNothing);
  });

  testWidgets('Show as a list reveals the exact wake times', (t) async {
    await pump(t, WakeRhythmChart(days: fortnight(), use24h: true));
    expect(find.text('07:40'), findsNothing);

    await t.tap(find.byKey(const Key('rhythm-list-toggle')));
    await t.pumpAndSettle();

    // 18 July rang 06:45 and was dismissed 55 minutes later.
    expect(find.text('07:40'), findsOneWidget);
    expect(find.text('Show as a chart'), findsOneWidget);
  });

  testWidgets('the list omits days that never had an alarm', (t) async {
    final days = buildRhythm([ev(26, after: 3)], now, days: 5);
    await pump(t, WakeRhythmChart(days: days, use24h: true));
    await t.tap(find.byKey(const Key('rhythm-list-toggle')));
    await t.pumpAndSettle();
    expect(find.text('06:48'), findsOneWidget);
    expect(find.text('—'), findsNothing);
  });

  testWidgets('compact drops the legend and the toggle', (t) async {
    await pump(t, WakeRhythmChart(days: fortnight(), compact: true));
    expect(find.byKey(const Key('rhythm-list-toggle')), findsNothing);
    expect(find.text(outcomeLabel(RhythmOutcome.onTime)), findsNothing);
  });

  testWidgets('survives a narrow phone without overflowing', (t) async {
    await pump(t, WakeRhythmChart(days: fortnight()), wide: false);
    expect(t.takeException(), isNull);
  });

  testWidgets('a single morning still plots, thanks to the minimum span',
      (t) async {
    await pump(t, WakeRhythmChart(days: buildRhythm([ev(26, after: 3)], now, days: 3)));
    expect(t.takeException(), isNull);
  });
}
