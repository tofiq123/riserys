import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/alarm.dart';
import 'package:rise/domain/rise_settings.dart';
import 'package:rise/domain/wake_event.dart';
import 'package:rise/ui/components/slide_to_wake.dart';
import 'package:rise/ui/missions/hold_mission.dart';
import 'package:rise/ui/missions/math_mission.dart';
import 'package:rise/ui/missions/memory_mission.dart';
import 'package:rise/ui/missions/mission_host.dart';
import 'package:rise/ui/missions/pvt_mission.dart';
import 'package:rise/ui/missions/tap_mission.dart';
import 'package:rise/ui/screens/ring_screen.dart';
import 'package:rise/ui/state/alarm_providers.dart';
import 'package:rise/ui/state/settings_providers.dart';
import 'package:rise/ui/state/wake_providers.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  group('MathMission', () {
    testWidgets('correct answer solves', (t) async {
      var solved = false;
      await t.pumpWidget(_wrap(MathMission(
        diff: 'easy',
        onSolved: () => solved = true,
        problem: (prompt: '2 + 3', answer: 5),
      )));
      await t.enterText(find.byType(TextField), '5');
      await t.tap(find.text('Check'));
      await t.pump();
      expect(solved, isTrue);
    });

    testWidgets('wrong answer does not solve and shows a retry hint', (t) async {
      var solved = false;
      await t.pumpWidget(_wrap(MathMission(
        diff: 'easy',
        onSolved: () => solved = true,
        problem: (prompt: '2 + 3', answer: 5),
      )));
      await t.enterText(find.byType(TextField), '9');
      await t.tap(find.text('Check'));
      await t.pump();
      expect(solved, isFalse);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('tapping Check again after solving does not re-fire onSolved', (t) async {
      var solves = 0;
      await t.pumpWidget(_wrap(MathMission(
        diff: 'easy',
        onSolved: () => solves++,
        problem: (prompt: '2 + 3', answer: 5),
      )));
      await t.enterText(find.byType(TextField), '5');
      await t.tap(find.text('Check'));
      await t.pump();
      expect(solves, 1);
      await t.tap(find.text('Check')); // text still '5', already solved
      await t.pump();
      expect(solves, 1);
    });
  });

  test('generateMathProblem answer matches its printed operands', () {
    for (final d in ['easy', 'medium', 'hard']) {
      final p = generateMathProblem(d);
      final parts = p.prompt.split(' '); // "a + b" or "a × b"
      final a = int.parse(parts[0]);
      final b = int.parse(parts[2]);
      final expected = parts[1] == '×' ? a * b : a + b;
      expect(p.answer, expected, reason: 'diff $d: ${p.prompt}');
    }
  });

  group('HoldMission', () {
    testWidgets('holding until the timer completes solves', (t) async {
      var solved = false;
      await t.pumpWidget(_wrap(HoldMission(
        diff: 'easy',
        onSolved: () => solved = true,
        holdDuration: const Duration(milliseconds: 100),
      )));
      final g = await t.startGesture(t.getCenter(find.text('HOLD')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 130));
      expect(solved, isTrue);
      await g.up();
    });

    testWidgets('releasing early does not solve', (t) async {
      var solved = false;
      await t.pumpWidget(_wrap(HoldMission(
        diff: 'easy',
        onSolved: () => solved = true,
        holdDuration: const Duration(milliseconds: 100),
      )));
      final g = await t.startGesture(t.getCenter(find.text('HOLD')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 40));
      await g.up();
      await t.pump(const Duration(milliseconds: 200));
      expect(solved, isFalse);
    });

    testWidgets('holding again after completion does not re-fire onSolved', (t) async {
      var solves = 0;
      await t.pumpWidget(_wrap(HoldMission(
        diff: 'easy',
        onSolved: () => solves++,
        holdDuration: const Duration(milliseconds: 100),
      )));
      final g = await t.startGesture(t.getCenter(find.text('HOLD')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 130));
      await g.up();
      expect(solves, 1);
      final g2 = await t.startGesture(t.getCenter(find.text('HOLD')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 130));
      await g2.up();
      expect(solves, 1);
    });
  });

  testWidgets('TapMission: reaching the target solves', (t) async {
    var solved = false;
    await t.pumpWidget(_wrap(TapMission(
      diff: 'easy',
      onSolved: () => solved = true,
      targetTaps: 3,
    )));
    await t.tap(find.text('3'));
    await t.pump();
    await t.tap(find.text('2'));
    await t.pump();
    await t.tap(find.text('1'));
    await t.pump();
    expect(solved, isTrue);
  });

  group('MemoryMission', () {
    testWidgets('repeating the shown sequence solves', (t) async {
      var solved = false;
      await t.pumpWidget(_wrap(MemoryMission(
        diff: 'easy',
        onSolved: () => solved = true,
        sequence: const [0, 1, 2],
      )));
      await t.pump(); // start playback
      await t.pump(const Duration(seconds: 2)); // playback done, input opens
      await t.tap(find.byKey(const ValueKey('mem-pad-0')));
      await t.tap(find.byKey(const ValueKey('mem-pad-1')));
      await t.tap(find.byKey(const ValueKey('mem-pad-2')));
      await t.pump();
      expect(solved, isTrue);
    });

    testWidgets('a wrong tap does not solve', (t) async {
      var solved = false;
      await t.pumpWidget(_wrap(MemoryMission(
        diff: 'easy',
        onSolved: () => solved = true,
        sequence: const [0, 1, 2],
      )));
      await t.pump();
      await t.pump(const Duration(seconds: 2));
      await t.tap(find.byKey(const ValueKey('mem-pad-3'))); // wrong first pad
      await t.pump();
      expect(solved, isFalse);
    });

    testWidgets('extra taps after solving do not crash or re-solve', (t) async {
      var solves = 0;
      await t.pumpWidget(_wrap(MemoryMission(
        diff: 'easy',
        onSolved: () => solves++,
        sequence: const [0, 1, 2],
      )));
      await t.pump();
      await t.pump(const Duration(seconds: 2));
      await t.tap(find.byKey(const ValueKey('mem-pad-0')));
      await t.tap(find.byKey(const ValueKey('mem-pad-1')));
      await t.tap(find.byKey(const ValueKey('mem-pad-2')));
      await t.pump();
      expect(solves, 1);
      await t.tap(find.byKey(const ValueKey('mem-pad-3'))); // stray tap after solve
      await t.pump();
      expect(t.takeException(), isNull); // no RangeError
      expect(solves, 1);
    });
  });

  group('buildMission host', () {
    testWidgets('dispatches to the right mission widget', (t) async {
      final cases = <String, Type>{
        'math': MathMission,
        'hold': HoldMission,
        'tap': TapMission,
        'memory': MemoryMission,
        'pvt': PvtMission,
      };
      for (final entry in cases.entries) {
        await t.pumpWidget(_wrap(Builder(
          builder: (context) => buildMission(
            context,
            Alarm(id: 1, hour: 6, minute: 0, mission: entry.key),
            () {},
          ),
        )));
        await t.pump();
        expect(find.byType(entry.value), findsOneWidget,
            reason: 'mission ${entry.key}');
      }
    });

    testWidgets('pvt forwards the alertness callback into PvtMission.onResult',
        (t) async {
      void onAlertness(int _) {}
      await t.pumpWidget(_wrap(Builder(
        builder: (context) => buildMission(
          context,
          const Alarm(id: 1, hour: 6, minute: 0, mission: 'pvt'),
          () {},
          onAlertness,
        ),
      )));
      await t.pump();
      final mission = t.widget<PvtMission>(find.byType(PvtMission));
      expect(mission.onResult, same(onAlertness));
    });

    testWidgets('a non-pvt mission ignores the alertness callback', (t) async {
      // Passing onAlertness to a non-PVT mission is a harmless no-op: the mission
      // still renders and never touches the callback.
      await t.pumpWidget(_wrap(Builder(
        builder: (context) => buildMission(
          context,
          const Alarm(id: 1, hour: 6, minute: 0, mission: 'tap'),
          () {},
          (int _) => fail('non-pvt mission must not report an alertness score'),
        ),
      )));
      await t.pump();
      expect(find.byType(TapMission), findsOneWidget);
    });

    testWidgets('buildMission falls back to slide-to-wake for an unknown key', (t) async {
      await t.pumpWidget(_wrap(Builder(
        builder: (context) => buildMission(
          context,
          const Alarm(id: 1, hour: 6, minute: 0, mission: 'photo'), // not a known key
          () {},
        ),
      )));
      await t.pump();
      expect(find.byType(SlideToWake), findsOneWidget);
    });

    testWidgets('RingScreen with the host shows the mission for a missioned alarm',
        (t) async {
      await t.pumpWidget(ProviderScope(
        overrides: [
          alarmsProvider.overrideWith((ref) => Stream.value(
              const [Alarm(id: 7, hour: 6, minute: 30, mission: 'tap')])),
          currentSettingsProvider.overrideWithValue(const RiseSettings()),
          wakeEventsProvider.overrideWith((ref) => Stream.value(const <WakeEvent>[])),
        ],
        child: MaterialApp(
          home: RingScreen(
            alarmId: 7,
            dismissAlarm: (_) async {},
            missionBuilder: buildMission,
          ),
        ),
      ));
      await t.pump();
      expect(find.byType(TapMission), findsOneWidget);
      expect(find.byType(SlideToWake), findsNothing);
    });
  });
}
