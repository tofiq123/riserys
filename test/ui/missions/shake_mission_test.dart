import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/alarm.dart';
import 'package:rise/ui/missions/mission_host.dart';
import 'package:rise/ui/missions/shake_mission.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  group('shakeTargetFor', () {
    test('scales with difficulty', () {
      expect(shakeTargetFor('easy'), 10);
      expect(shakeTargetFor('medium'), 20);
      expect(shakeTargetFor('hard'), 30);
      expect(shakeTargetFor('nonsense'), 10, reason: 'unknown -> easy');
    });
  });

  group('gForceMagnitude', () {
    test('a phone at rest reads about 1 g', () {
      expect(gForceMagnitude(0, 0, 9.80665), closeTo(1.0, 0.001));
    });
    test('a brisk shake exceeds the default 2.7 g threshold', () {
      expect(gForceMagnitude(0, 0, 40) > 2.7, isTrue);
    });
  });

  group('ShakeDetector', () {
    test('a spike over threshold counts as one shake', () {
      final d = ShakeDetector();
      expect(d.onSample(0, 0, 40, 0), isTrue);
      expect(d.count, 1);
    });

    test('a below-threshold sample does not count', () {
      final d = ShakeDetector();
      expect(d.onSample(0, 0, 9.8, 0), isFalse, reason: 'resting ~1 g');
      expect(d.count, 0);
    });

    test('two spikes within the min gap collapse to a single shake', () {
      final d = ShakeDetector(minGapMs: 400);
      expect(d.onSample(0, 0, 40, 0), isTrue);
      expect(d.onSample(0, 0, 40, 399), isFalse, reason: 'still within the gap');
      expect(d.count, 1);
    });

    test('spikes spaced beyond the min gap each count', () {
      final d = ShakeDetector(minGapMs: 400);
      expect(d.onSample(0, 0, 40, 0), isTrue);
      expect(d.onSample(0, 0, 40, 400), isTrue);
      expect(d.onSample(0, 0, 40, 900), isTrue);
      expect(d.count, 3);
    });
  });

  testWidgets('reaching the shake target solves', (t) async {
    var solves = 0;
    var now = 0;
    final ctrl = StreamController<({double x, double y, double z})>();
    addTearDown(ctrl.close);

    await t.pumpWidget(_wrap(ShakeMission(
      diff: 'easy',
      onSolved: () => solves++,
      targetShakes: 3,
      sampleStream: ctrl.stream,
      nowMs: () => now,
    )));

    for (var i = 0; i < 3; i++) {
      ctrl.add((x: 0, y: 0, z: 40));
      await t.pump();
      now += 500; // clear the debounce gap before the next spike
    }

    expect(solves, 1);
  });

  testWidgets('below-threshold samples never solve', (t) async {
    var solves = 0;
    var now = 0;
    final ctrl = StreamController<({double x, double y, double z})>();
    addTearDown(ctrl.close);

    await t.pumpWidget(_wrap(ShakeMission(
      diff: 'easy',
      onSolved: () => solves++,
      targetShakes: 2,
      sampleStream: ctrl.stream,
      nowMs: () => now,
    )));

    for (var i = 0; i < 10; i++) {
      ctrl.add((x: 0, y: 0, z: 9.8)); // resting ~1 g, no shake
      await t.pump();
      now += 500;
    }

    expect(solves, 0);
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
