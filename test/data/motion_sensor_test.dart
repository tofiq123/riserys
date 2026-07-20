import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/motion_sensor.dart';

void main() {
  // A short window keeps these fast; the injected stream stands in for the
  // platform pedometer so no real sensor is touched.
  const window = Duration(milliseconds: 60);

  test('accumulated steps over the window → sustained motion', () async {
    final sensor = MotionSensor(stepStream: Stream.fromIterable([100, 110, 124]));
    expect(await sensor.sensedSustainedMotion(window), isTrue);
  });

  test('barely any movement → not sustained', () async {
    final sensor = MotionSensor(stepStream: Stream.fromIterable([100, 102]));
    expect(await sensor.sensedSustainedMotion(window), isFalse);
  });

  test('no readings within the window → not sustained (unknown)', () async {
    final sensor = MotionSensor(stepStream: Stream<int>.empty());
    expect(await sensor.sensedSustainedMotion(window), isFalse);
  });

  test('a stream error resolves to not sustained and never throws', () async {
    final sensor = MotionSensor(
      stepStream: Stream<int>.error(StateError('no step sensor')),
    );
    expect(await sensor.sensedSustainedMotion(window), isFalse);
  });

  test('honours a custom threshold (below trips, above does not)', () async {
    // Fresh single-subscription streams per call.
    final low = MotionSensor(stepStream: Stream.fromIterable([0, 7]));
    expect(await low.sensedSustainedMotion(window, threshold: 5), isTrue);
    final high = MotionSensor(stepStream: Stream.fromIterable([0, 7]));
    expect(await high.sensedSustainedMotion(window, threshold: 20), isFalse);
  });
}
