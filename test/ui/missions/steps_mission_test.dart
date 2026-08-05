import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/alarm.dart';
import 'package:rise/ui/components/slide_to_wake.dart';
import 'package:rise/ui/missions/mission_host.dart';
import 'package:rise/ui/missions/steps_mission.dart';

// A bounded width so the slide-to-wake fallback's LayoutBuilder has finite
// travel to compute against.
Widget _wrap(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: SizedBox(width: 340, child: child))));

void main() {
  group('stepTargetFor', () {
    test('scales with difficulty', () {
      expect(stepTargetFor('easy'), 10);
      expect(stepTargetFor('medium'), 20);
      expect(stepTargetFor('hard'), 40);
      expect(stepTargetFor('nonsense'), 10, reason: 'unknown -> easy');
    });
  });

  group('stepGoalReached', () {
    test('true once the delta from baseline reaches target', () {
      expect(stepGoalReached(1000, 1010, 10), isTrue);
      expect(stepGoalReached(1000, 1011, 10), isTrue);
    });
    test('false while short of target', () {
      expect(stepGoalReached(1000, 1009, 10), isFalse);
    });
  });

  testWidgets('reaching the step target solves', (t) async {
    var solves = 0;
    final ctrl = StreamController<int>();
    addTearDown(ctrl.close);

    await t.pumpWidget(_wrap(StepsMission(
      diff: 'easy',
      onSolved: () => solves++,
      targetSteps: 10,
      stepCountStream: ctrl.stream,
      fallbackAfter: const Duration(hours: 1), // never fires in this test
      requestPermission: () async => true,
    )));
    await t.pump();
    await t.pump(); // let the permission check resolve before subscribing

    ctrl.add(1000); // baseline anchor
    await t.pump();
    expect(solves, 0);
    ctrl.add(1010); // delta 10 -> goal
    await t.pump();
    expect(solves, 1);
  });

  testWidgets('the baseline anchors on the first reading (large boot counts)',
      (t) async {
    var solves = 0;
    final ctrl = StreamController<int>();
    addTearDown(ctrl.close);

    await t.pumpWidget(_wrap(StepsMission(
      diff: 'easy',
      onSolved: () => solves++,
      targetSteps: 5,
      stepCountStream: ctrl.stream,
      fallbackAfter: const Duration(hours: 1),
      requestPermission: () async => true,
    )));
    await t.pump();
    await t.pump(); // let the permission check resolve before subscribing

    ctrl.add(48210); // huge cumulative count -> baseline, not an instant solve
    await t.pump();
    expect(solves, 0);
    ctrl.add(48214); // delta 4 < 5
    await t.pump();
    expect(solves, 0);
    ctrl.add(48215); // delta 5 -> goal
    await t.pump();
    expect(solves, 1);
  });

  testWidgets('short of the target does not solve', (t) async {
    var solves = 0;
    final ctrl = StreamController<int>();
    addTearDown(ctrl.close);

    await t.pumpWidget(_wrap(StepsMission(
      diff: 'easy',
      onSolved: () => solves++,
      targetSteps: 10,
      stepCountStream: ctrl.stream,
      fallbackAfter: const Duration(hours: 1),
      requestPermission: () async => true,
    )));
    await t.pump();
    await t.pump(); // let the permission check resolve before subscribing

    ctrl.add(1000);
    await t.pump();
    ctrl.add(1005);
    await t.pump();
    expect(solves, 0);

    await t.pumpWidget(const SizedBox()); // dispose -> cancel the fallback timer
  });

  testWidgets('a stream error surfaces the slide-to-wake fallback', (t) async {
    var solves = 0;
    final ctrl = StreamController<int>();
    addTearDown(ctrl.close);

    await t.pumpWidget(_wrap(StepsMission(
      diff: 'easy',
      onSolved: () => solves++,
      targetSteps: 10,
      stepCountStream: ctrl.stream,
      fallbackAfter: const Duration(hours: 1),
      requestPermission: () async => true,
    )));
    await t.pump();
    await t.pump(); // let the permission check resolve before subscribing

    ctrl.addError(Exception('no ACTIVITY_RECOGNITION permission'));
    await t.pump();
    await t.pump();
    expect(find.byType(SlideToWake), findsOneWidget);
    expect(find.text("Can't count steps on this device"), findsOneWidget);

    await t.pumpWidget(const SizedBox()); // dispose -> cancel the fallback timer
  });

  testWidgets('the timeout fallback appears and its slide dismisses (anti-trap)',
      (t) async {
    var solves = 0;
    final ctrl = StreamController<int>();
    addTearDown(ctrl.close);

    await t.pumpWidget(_wrap(StepsMission(
      diff: 'easy',
      onSolved: () => solves++,
      targetSteps: 10,
      stepCountStream: ctrl.stream,
      fallbackAfter: const Duration(milliseconds: 100),
      requestPermission: () async => true,
    )));
    await t.pump();
    await t.pump(); // let the permission check resolve before subscribing

    // No step events arrive; the fallback timer fires.
    await t.pump(const Duration(milliseconds: 150));
    expect(find.byType(SlideToWake), findsOneWidget);

    // The escape actually dismisses — the user is never trapped.
    await t.drag(find.byType(SlideToWake), const Offset(600, 0));
    await t.pump();
    expect(solves, 1);
  });

  testWidgets(
      'denied permission shows the fallback immediately, without waiting for the timeout',
      (t) async {
    var solves = 0;

    // No stepCountStream: denied permission means the mission never
    // subscribes at all (see _requestPermissionThenListen), so there is
    // nothing for a stream to do here.
    await t.pumpWidget(_wrap(StepsMission(
      diff: 'easy',
      onSolved: () => solves++,
      targetSteps: 10,
      fallbackAfter: const Duration(hours: 1), // must not need to wait for this
      requestPermission: () async => false,
    )));
    await t.pump();
    await t.pump();

    expect(find.byType(SlideToWake), findsOneWidget);

    // The escape still dismisses — anti-trap holds even on a denied permission.
    await t.drag(find.byType(SlideToWake), const Offset(600, 0));
    await t.pump();
    expect(solves, 1);
  });

  testWidgets(
      'a permission-check failure never blocks the mission — it just proceeds',
      (t) async {
    var solves = 0;
    final ctrl = StreamController<int>();
    addTearDown(ctrl.close);

    await t.pumpWidget(_wrap(StepsMission(
      diff: 'easy',
      onSolved: () => solves++,
      targetSteps: 10,
      stepCountStream: ctrl.stream,
      fallbackAfter: const Duration(hours: 1),
      requestPermission: () async => throw StateError('plugin unavailable'),
    )));
    await t.pump();
    await t.pump();

    // Subscribed anyway (fail-open), so real step events still solve it.
    ctrl.add(1000);
    await t.pump();
    ctrl.add(1010);
    await t.pump();
    expect(solves, 1);
  });

  testWidgets('buildMission dispatches to StepsMission without rendering it',
      (t) async {
    // Rendering would subscribe to the platform pedometer, so only the returned
    // widget type is asserted here — never pumped.
    late BuildContext ctx;
    await t.pumpWidget(_wrap(Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    final w = buildMission(
        ctx, const Alarm(id: 1, hour: 6, minute: 0, mission: 'steps'), () {});
    expect(w, isA<StepsMission>());
  });
}
