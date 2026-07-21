import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/alarm.dart';
import 'package:rise/ui/components/slide_to_wake.dart';
import 'package:rise/ui/missions/mission_host.dart';
import 'package:rise/ui/missions/shake_mission.dart';

// A bounded width so the slide-to-wake fallback's LayoutBuilder has finite
// travel to compute against.
Widget _wrap(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: SizedBox(width: 340, child: child))));

void main() {
  group('shakeRequiredMsFor', () {
    test('scales with difficulty', () {
      expect(shakeRequiredMsFor('easy'), 3000);
      expect(shakeRequiredMsFor('medium'), 5000);
      expect(shakeRequiredMsFor('hard'), 7000);
      expect(shakeRequiredMsFor('nonsense'), 3000, reason: 'unknown -> easy');
    });
  });

  group('gForceMagnitude', () {
    test('a phone at rest reads about 1 g', () {
      expect(gForceMagnitude(0, 0, 9.80665), closeTo(1.0, 0.001));
    });
    test('a brisk shake exceeds the default 2.2 g gate', () {
      expect(gForceMagnitude(0, 0, 40) > 2.2, isTrue);
    });
  });

  group('SustainedShakeDetector', () {
    test('steady shaking fills to completion at ~wall-clock rate', () {
      final d = SustainedShakeDetector(requiredMs: 1000);
      var done = false;
      for (var i = 0; i < 10; i++) {
        done = d.onSample(3.0, 100); // 3 g, 100ms slice, all above the 2.2 g gate
      }
      expect(done, isTrue);
      expect(d.isComplete, isTrue);
      expect(d.progress, 1.0);
    });

    test('progress reports the fraction filled and clamps at 1.0', () {
      final d = SustainedShakeDetector(requiredMs: 1000);
      d.onSample(3.0, 250);
      expect(d.progress, closeTo(0.25, 1e-9));
      d.onSample(3.0, 300);
      expect(d.progress, closeTo(0.55, 1e-9));
      for (var i = 0; i < 5; i++) {
        d.onSample(3.0, 200); // overshoot
      }
      expect(d.activeMs, 1000, reason: 'clamped to requiredMs');
      expect(d.progress, 1.0);
    });

    test('a brief trough between swings still counts as shaking', () {
      final d = SustainedShakeDetector(requiredMs: 1000, graceMs: 350);
      for (var i = 0; i < 5; i++) {
        d.onSample(4.0, 100); // swing (above the gate)
        d.onSample(1.0, 100); // reversal trough (below), but within grace
      }
      // Both the swings and the short troughs count: 5 * 200ms = 1000ms.
      expect(d.isComplete, isTrue);
    });

    test('being held still past the grace window resets progress', () {
      final d = SustainedShakeDetector(requiredMs: 1000, graceMs: 350);
      d.onSample(4.0, 100);
      d.onSample(4.0, 100);
      d.onSample(4.0, 100);
      expect(d.activeMs, 300);
      // Dense stillness accrues calm until it passes the grace window, then wipes.
      d.onSample(1.0, 100);
      d.onSample(1.0, 100);
      d.onSample(1.0, 100);
      d.onSample(1.0, 100); // cumulative calm 400 >= 350 -> reset
      expect(d.activeMs, 0);
      expect(d.progress, 0.0);
      expect(d.isComplete, isFalse);
    });

    test('sparse flicks separated by pauses never accumulate', () {
      final d = SustainedShakeDetector(requiredMs: 1000, graceMs: 350);
      for (var i = 0; i < 20; i++) {
        d.onSample(5.0, 50); // a single flick
        d.onSample(1.0, 1000); // then a full second of stillness -> lapse
        expect(d.isComplete, isFalse);
      }
      expect(d.progress, 0.0);
    });

    test('a long sampling gap does not over-credit a lone reading', () {
      // e.g. the stream pauses on app-background and resumes with one big-dt
      // sample — it must not bank the whole unobserved span.
      final d = SustainedShakeDetector(requiredMs: 1000, graceMs: 350);
      final done = d.onSample(9.0, 5000); // 5s gap, then a big spike
      expect(done, isFalse);
      expect(d.activeMs, 0);
    });
  });

  testWidgets('sustained shaking reaches the window and solves', (t) async {
    var solves = 0;
    var now = 0;
    final ctrl = StreamController<({double x, double y, double z})>();
    addTearDown(ctrl.close);

    await t.pumpWidget(_wrap(ShakeMission(
      diff: 'easy',
      onSolved: () => solves++,
      requiredMs: 500,
      sampleStream: ctrl.stream,
      nowMs: () => now,
      fallbackAfter: const Duration(hours: 1),
    )));

    // Steady above-gate samples 50ms apart; the first anchors dt=0.
    for (var i = 0; i < 12; i++) {
      ctrl.add((x: 0, y: 0, z: 40)); // ~4 g
      await t.pump();
      now += 50;
    }

    expect(solves, 1);
  });

  testWidgets('intermittent shaking with long pauses never solves (resets)',
      (t) async {
    var solves = 0;
    var now = 0;
    final ctrl = StreamController<({double x, double y, double z})>();
    addTearDown(ctrl.close);

    await t.pumpWidget(_wrap(ShakeMission(
      diff: 'easy',
      onSolved: () => solves++,
      requiredMs: 500,
      sampleStream: ctrl.stream,
      nowMs: () => now,
      fallbackAfter: const Duration(hours: 1),
    )));

    // One shake, then a >grace pause, repeated: progress keeps resetting.
    for (var i = 0; i < 8; i++) {
      ctrl.add((x: 0, y: 0, z: 40)); // shake
      await t.pump();
      now += 100;
      ctrl.add((x: 0, y: 0, z: 9.8)); // rest
      await t.pump();
      now += 500; // long pause -> the next reading lands after a grace-long gap
    }

    expect(solves, 0);
    await t.pumpWidget(const SizedBox()); // dispose -> cancel the fallback timer
  });

  testWidgets('the meter partially fills as shaking accumulates', (t) async {
    var now = 0;
    final ctrl = StreamController<({double x, double y, double z})>();
    addTearDown(ctrl.close);

    await t.pumpWidget(_wrap(ShakeMission(
      diff: 'easy',
      onSolved: () {},
      requiredMs: 1000,
      sampleStream: ctrl.stream,
      nowMs: () => now,
      fallbackAfter: const Duration(hours: 1),
    )));

    for (var i = 0; i < 3; i++) {
      ctrl.add((x: 0, y: 0, z: 40));
      await t.pump();
      now += 100;
    }

    final meter = t.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator));
    expect(meter.value, isNotNull);
    expect(meter.value! > 0 && meter.value! < 1, isTrue,
        reason: 'partially filled, not yet complete');

    await t.pumpWidget(const SizedBox());
  });

  testWidgets('below-threshold samples never solve', (t) async {
    var solves = 0;
    var now = 0;
    final ctrl = StreamController<({double x, double y, double z})>();
    addTearDown(ctrl.close);

    await t.pumpWidget(_wrap(ShakeMission(
      diff: 'easy',
      onSolved: () => solves++,
      requiredMs: 200,
      sampleStream: ctrl.stream,
      nowMs: () => now,
      fallbackAfter: const Duration(hours: 1),
    )));

    for (var i = 0; i < 20; i++) {
      ctrl.add((x: 0, y: 0, z: 9.8)); // resting ~1 g, no shake
      await t.pump();
      now += 50;
    }

    expect(solves, 0);
    await t.pumpWidget(const SizedBox()); // dispose -> cancel the fallback timer
  });

  testWidgets('a sensor stream error surfaces the slide-to-wake fallback',
      (t) async {
    var solves = 0;
    final ctrl = StreamController<({double x, double y, double z})>();
    addTearDown(ctrl.close);

    await t.pumpWidget(_wrap(ShakeMission(
      diff: 'easy',
      onSolved: () => solves++,
      requiredMs: 500,
      sampleStream: ctrl.stream,
      fallbackAfter: const Duration(hours: 1),
    )));

    ctrl.addError(Exception('accelerometer unavailable'));
    await t.pump();
    expect(find.byType(SlideToWake), findsOneWidget);
    expect(find.text("Can't read motion on this device"), findsOneWidget);

    await t.pumpWidget(const SizedBox()); // dispose -> cancel the fallback timer
  });

  testWidgets('the timeout fallback appears and its slide dismisses (anti-trap)',
      (t) async {
    var solves = 0;
    final ctrl = StreamController<({double x, double y, double z})>();
    addTearDown(ctrl.close);

    await t.pumpWidget(_wrap(ShakeMission(
      diff: 'easy',
      onSolved: () => solves++,
      requiredMs: 500,
      sampleStream: ctrl.stream, // never emits
      fallbackAfter: const Duration(milliseconds: 100),
    )));

    await t.pump(const Duration(milliseconds: 150)); // fallback timer fires
    expect(find.byType(SlideToWake), findsOneWidget);

    // The escape actually dismisses — the user is never trapped.
    await t.drag(find.byType(SlideToWake), const Offset(600, 0));
    await t.pump();
    expect(solves, 1);
  });

  testWidgets('buildMission dispatches to ShakeMission without rendering it',
      (t) async {
    // Rendering ShakeMission would subscribe to the platform accelerometer,
    // so only the returned widget type is asserted here — never pumped.
    late BuildContext ctx;
    await t.pumpWidget(_wrap(Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    final w = buildMission(
        ctx, const Alarm(id: 1, hour: 6, minute: 0, mission: 'shake'), () {});
    expect(w, isA<ShakeMission>());
  });
}
