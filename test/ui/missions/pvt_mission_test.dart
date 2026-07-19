import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/pvt.dart';
import 'package:rise/ui/missions/pvt_mission.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  group('PvtMission', () {
    testWidgets(
        'a tap during the wait phase is a false start and does not solve; '
        'tapping after the ISI records a reaction time and solves',
        (t) async {
      var nowValue = 1000;
      var solves = 0;
      int? reportedScore;

      await t.pumpWidget(_wrap(PvtMission(
        diff: 'easy',
        onSolved: () => solves++,
        onResult: (score) => reportedScore = score,
        config: const PvtConfig(
            trials: 1, isiMinMs: 40, isiMaxMs: 40, lapseThresholdMs: 355),
        scriptedIsiMs: const [40],
        nowMs: () => nowValue,
      )));

      // Still within the ISI: a tap here is a false start, not a solve.
      expect(find.text('Wait…'), findsOneWidget);
      await t.tap(find.text('Wait…'));
      await t.pump();
      expect(solves, 0);
      expect(reportedScore, isNull);
      expect(find.text('Wait…'), findsOneWidget); // restarted the same wait

      // Let the (restarted) ISI elapse -> stimulus phase.
      await t.pump(const Duration(milliseconds: 40));
      expect(find.text('TAP!'), findsOneWidget);

      // Simulate a 300ms reaction, then tap.
      nowValue += 300;
      await t.tap(find.text('TAP!'));
      await t.pump();

      expect(solves, 1);
      expect(reportedScore, isNotNull);
      expect(reportedScore, inInclusiveRange(0, 100));
    });

    testWidgets('tapping again after the mission solves does not re-fire onSolved',
        (t) async {
      var nowValue = 0;
      var solves = 0;

      await t.pumpWidget(_wrap(PvtMission(
        diff: 'easy',
        onSolved: () => solves++,
        config: const PvtConfig(
            trials: 1, isiMinMs: 10, isiMaxMs: 10, lapseThresholdMs: 355),
        scriptedIsiMs: const [10],
        nowMs: () => nowValue,
      )));

      await t.pump(const Duration(milliseconds: 10));
      await t.tap(find.text('TAP!'));
      await t.pump();
      expect(solves, 1);

      // No more target to tap — pumping further must not crash or re-fire.
      await t.pump(const Duration(milliseconds: 500));
      expect(t.takeException(), isNull);
      expect(solves, 1);
    });

    testWidgets('trial progress advances only on valid taps, not false starts',
        (t) async {
      var nowValue = 0;

      await t.pumpWidget(_wrap(PvtMission(
        diff: 'easy',
        onSolved: () {},
        config: const PvtConfig(
            trials: 2, isiMinMs: 10, isiMaxMs: 10, lapseThresholdMs: 355),
        scriptedIsiMs: const [10, 10],
        nowMs: () => nowValue,
      )));

      expect(find.text('0 / 2'), findsOneWidget);
      await t.tap(find.text('Wait…')); // false start — does not advance
      await t.pump();
      expect(find.text('0 / 2'), findsOneWidget);

      await t.pump(const Duration(milliseconds: 10));
      await t.tap(find.text('TAP!'));
      await t.pump();
      expect(find.text('1 / 2'), findsOneWidget);
    });
  });
}
