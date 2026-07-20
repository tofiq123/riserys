import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/motion_consensus.dart';

void main() {
  group('MotionConsensus.sustained', () {
    test('enough accumulated steps across the window → sustained', () {
      // 100 → 120 = 20 steps, over the default threshold of 12.
      expect(MotionConsensus.sustained([100, 108, 120]), isTrue);
    });

    test('a delta exactly at the threshold counts (>=)', () {
      expect(MotionConsensus.sustained([100, 112]), isTrue);
    });

    test('too few steps (a shift in bed) → not sustained', () {
      expect(MotionConsensus.sustained([100, 104]), isFalse);
    });

    test('fewer than two samples is never sustained (no evidence)', () {
      expect(MotionConsensus.sustained([]), isFalse);
      expect(MotionConsensus.sustained([500]), isFalse);
    });

    test('a counter reset / reboot (negative delta) is not sustained', () {
      // Reboot mid-window: cumulative counter dropped. Conservative → false.
      expect(MotionConsensus.sustained([5000, 30]), isFalse);
    });

    test('a zero delta (perfectly still) is not sustained', () {
      expect(MotionConsensus.sustained([200, 200, 200]), isFalse);
    });

    test('honours a custom threshold', () {
      expect(MotionConsensus.sustained([0, 6], threshold: 5), isTrue);
      expect(MotionConsensus.sustained([0, 6], threshold: 20), isFalse);
    });

    test('only the first and last readings anchor the delta', () {
      // Baseline 100, ends at 130 → 30 steps regardless of the dip between.
      expect(MotionConsensus.sustained([100, 101, 130]), isTrue);
    });
  });

  group('MotionConsensus.netSteps', () {
    test('computes the first → last delta', () {
      expect(MotionConsensus.netSteps([100, 108, 125]), 25);
    });

    test('clamps a counter reset to zero', () {
      expect(MotionConsensus.netSteps([5000, 30]), 0);
    });

    test('fewer than two samples → 0', () {
      expect(MotionConsensus.netSteps([]), 0);
      expect(MotionConsensus.netSteps([42]), 0);
    });
  });
}
