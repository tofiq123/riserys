import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/wake_confidence.dart';

void main() {
  group('wakeConfidence', () {
    test('sustained motion alone is a strong signal (clears the bar)', () {
      final c = wakeConfidence(
          sustainedMotion: true, appInteracted: false, alertnessScore: null);
      expect(c, greaterThanOrEqualTo(kConfidentThreshold));
    });

    test('every signal present saturates at 100', () {
      expect(
          wakeConfidence(
              sustainedMotion: true, appInteracted: true, alertnessScore: 100),
          100);
    });

    test('still + no interaction + no alertness → zero (nothing to trust)', () {
      expect(
          wakeConfidence(
              sustainedMotion: false,
              appInteracted: false,
              alertnessScore: null),
          0);
    });

    test('motion is weighted strongest — it outweighs the soft signals combined',
        () {
      final motionOnly = wakeConfidence(
          sustainedMotion: true, appInteracted: false, alertnessScore: null);
      final softOnly = wakeConfidence(
          sustainedMotion: false, appInteracted: true, alertnessScore: 100);
      expect(motionOnly, greaterThan(softOnly));
    });

    test('a null alertness contributes nothing (missing → conservative)', () {
      final withNull = wakeConfidence(
          sustainedMotion: true, appInteracted: false, alertnessScore: null);
      final withZero = wakeConfidence(
          sustainedMotion: true, appInteracted: false, alertnessScore: 0);
      expect(withNull, withZero);
    });

    test('alertness scales into its band and is clamped to 0..100', () {
      final low = wakeConfidence(
          sustainedMotion: false, appInteracted: false, alertnessScore: 0);
      final high = wakeConfidence(
          sustainedMotion: false, appInteracted: false, alertnessScore: 100);
      expect(low, 0);
      expect(high, greaterThan(low));
      // Out-of-range inputs are clamped, never overflow the band.
      final over = wakeConfidence(
          sustainedMotion: false, appInteracted: false, alertnessScore: 500);
      final under = wakeConfidence(
          sustainedMotion: false, appInteracted: false, alertnessScore: -50);
      expect(over, high);
      expect(under, 0);
    });

    test('is always within 0..100', () {
      for (final m in [true, false]) {
        for (final i in [true, false]) {
          for (final a in [null, -10, 0, 50, 100, 999]) {
            final c = wakeConfidence(
                sustainedMotion: m, appInteracted: i, alertnessScore: a);
            expect(c, inInclusiveRange(0, 100));
          }
        }
      }
    });
  });

  group('wakeChallengeDecision', () {
    test('strong motion → confident (check satisfied, no re-ring)', () {
      expect(
          wakeChallengeDecision(
              sustainedMotion: true, appInteracted: false, alertnessScore: 80),
          WakeChallengeDecision.confident);
    });

    test('still + no interaction + absent alertness → reCheck (low)', () {
      expect(
          wakeChallengeDecision(
              sustainedMotion: false,
              appInteracted: false,
              alertnessScore: null),
          WakeChallengeDecision.reCheck);
    });

    test(
        'no motion never clears the bar, even with interaction + high alertness '
        '(you have to actually get up)', () {
      expect(
          wakeChallengeDecision(
              sustainedMotion: false, appInteracted: true, alertnessScore: 100),
          WakeChallengeDecision.reCheck);
    });

    test('all signals missing/unknown → reCheck (conservative default)', () {
      expect(
          wakeChallengeDecision(
              sustainedMotion: false,
              appInteracted: false,
              alertnessScore: null),
          WakeChallengeDecision.reCheck);
    });

    test('decision agrees with the threshold applied to the score', () {
      for (final m in [true, false]) {
        for (final i in [true, false]) {
          for (final a in [null, 0, 60, 100]) {
            final score = wakeConfidence(
                sustainedMotion: m, appInteracted: i, alertnessScore: a);
            final decision = wakeChallengeDecision(
                sustainedMotion: m, appInteracted: i, alertnessScore: a);
            expect(
                decision,
                score >= kConfidentThreshold
                    ? WakeChallengeDecision.confident
                    : WakeChallengeDecision.reCheck);
          }
        }
      }
    });
  });
}
