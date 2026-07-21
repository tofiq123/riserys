import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/eye_open.dart';

// Shorthand frame builder.
EyeFrame f(double? l, double? r, int dt) => (left: l, right: r, dtMs: dt);

void main() {
  group('eyeOpenWindowFor', () {
    test('scales a little with difficulty', () {
      expect(eyeOpenWindowFor('easy'), const Duration(milliseconds: 2000));
      expect(eyeOpenWindowFor('medium'), const Duration(milliseconds: 2500));
      expect(eyeOpenWindowFor('hard'), const Duration(milliseconds: 3500));
      expect(eyeOpenWindowFor('nonsense'), const Duration(milliseconds: 2000),
          reason: 'unknown -> easy');
    });
  });

  group('bothEyesOpen', () {
    test('true only when both probabilities clear the threshold', () {
      expect(bothEyesOpen(f(0.9, 0.8, 100)), isTrue);
      expect(bothEyesOpen(f(0.9, 0.5, 100)), isFalse, reason: 'right shut');
      expect(bothEyesOpen(f(0.4, 0.9, 100)), isFalse, reason: 'left shut');
    });

    test('a null probability (no live face / low confidence) is not open', () {
      expect(bothEyesOpen(f(null, 0.9, 100)), isFalse);
      expect(bothEyesOpen(f(0.9, null, 100)), isFalse);
      expect(bothEyesOpen(f(null, null, 100)), isFalse);
    });

    test('exactly at the threshold is not yet open (strictly greater)', () {
      expect(bothEyesOpen(f(0.6, 0.6, 100)), isFalse);
      expect(bothEyesOpen(f(0.61, 0.61, 100)), isTrue);
    });

    test('the threshold is adjustable', () {
      expect(bothEyesOpen(f(0.5, 0.5, 100), threshold: 0.4), isTrue);
    });
  });

  group('accumulateOpenMs / sustainedOpen', () {
    test('sums only the open-eyed frame durations', () {
      final frames = [
        f(0.9, 0.9, 200), // open   +200
        f(0.1, 0.1, 200), // closed  +0
        f(0.9, 0.9, 300), // open   +300
      ];
      expect(accumulateOpenMs(frames), 500);
    });

    test('reaches the required window across cumulative open frames', () {
      final frames = [
        f(0.9, 0.9, 800),
        f(0.9, 0.9, 800),
        f(0.9, 0.9, 800),
      ];
      expect(
          sustainedOpen(frames, const Duration(milliseconds: 2000)), isTrue);
    });

    test('blinks do not reset progress (cumulative, not consecutive)', () {
      // Open frames interleaved with blinks/lost-face still accumulate to goal.
      final frames = [
        f(0.9, 0.9, 700), // +700
        f(null, null, 100), // blink / lost face, +0, no reset
        f(0.9, 0.9, 700), // +1400
        f(0.05, 0.05, 100), // blink, +0
        f(0.9, 0.9, 700), // +2100
      ];
      expect(
          sustainedOpen(frames, const Duration(milliseconds: 2000)), isTrue);
    });

    test('eyes-shut frames never satisfy the window (defeats the sleepy swipe)',
        () {
      final frames = [
        f(0.1, 0.1, 1000),
        f(0.2, 0.05, 1000),
        f(null, null, 1000),
      ];
      expect(accumulateOpenMs(frames), 0);
      expect(
          sustainedOpen(frames, const Duration(milliseconds: 500)), isFalse);
    });

    test('short of the window does not solve', () {
      final frames = [f(0.9, 0.9, 500), f(0.9, 0.9, 500)];
      expect(
          sustainedOpen(frames, const Duration(milliseconds: 2000)), isFalse);
    });

    test('an empty stream is not solved', () {
      expect(sustainedOpen(const [], const Duration(milliseconds: 2000)),
          isFalse);
    });
  });
}
