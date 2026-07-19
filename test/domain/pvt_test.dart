import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/pvt.dart';

void main() {
  test('pvtConfigFor scales trials by difficulty', () {
    expect(pvtConfigFor('easy').trials, 3);
    expect(pvtConfigFor('medium').trials, 5);
    expect(pvtConfigFor('hard').trials, 7);
    expect(pvtConfigFor('easy').lapseThresholdMs, 355);
    expect(pvtConfigFor('easy').isiMinMs, 1500);
    expect(pvtConfigFor('easy').isiMaxMs, 4000);
  });

  test('computePvtResult computes metrics', () {
    final r = computePvtResult([250, 300, 400, 500], falseStarts: 1);
    expect(r.validTaps, 4);
    expect(r.meanRtMs, 363); // 1450/4 = 362.5 -> 363
    expect(r.medianRtMs, 350); // (300+400)/2
    expect(r.minRtMs, 250);
    expect(r.maxRtMs, 500);
    expect(r.lapses, 2); // >355: 400, 500
    expect(r.falseStarts, 1);
  });

  test('lapse counting at threshold 355', () {
    final r = computePvtResult([300, 356, 500], falseStarts: 0);
    expect(r.lapses, 2);
  });

  test('empty reaction times yield zeroed metrics', () {
    final r = computePvtResult([], falseStarts: 0);
    expect(r.validTaps, 0);
    expect(r.meanRtMs, 0);
    expect(r.medianRtMs, 0);
    expect(r.minRtMs, 0);
    expect(r.maxRtMs, 0);
    expect(r.lapses, 0);
    expect(r.falseStarts, 0);
  });

  test('falseStarts passed through even with taps', () {
    final r = computePvtResult([250, 260], falseStarts: 4);
    expect(r.falseStarts, 4);
  });

  test('alertnessScore: sharp session with no penalty', () {
    const r = PvtResult(
      validTaps: 4,
      lapses: 0,
      falseStarts: 0,
      meanRtMs: 250,
      medianRtMs: 250,
      minRtMs: 250,
      maxRtMs: 250,
    );
    // rtComponent = 100*(600-250)/380 = 92.1 -> 92, no penalty.
    expect(alertnessScore(r), 92);
  });

  test('alertnessScore: groggy session with lapse penalty', () {
    const r = PvtResult(
      validTaps: 5,
      lapses: 3,
      falseStarts: 0,
      meanRtMs: 480,
      medianRtMs: 480,
      minRtMs: 480,
      maxRtMs: 480,
    );
    // rtComponent = 100*(600-480)/380 = 31.6; penalty = 24; 31.6-24=7.6 -> 8.
    expect(alertnessScore(r), 8);
  });

  test('alertnessScore: meanRtMs below 220 clamps rtComponent to 100', () {
    const r = PvtResult(
      validTaps: 3,
      lapses: 0,
      falseStarts: 0,
      meanRtMs: 180,
      medianRtMs: 180,
      minRtMs: 180,
      maxRtMs: 180,
    );
    expect(alertnessScore(r), 100);
  });

  test('alertnessScore: zero valid taps returns 0', () {
    const r = PvtResult(
      validTaps: 0,
      lapses: 0,
      falseStarts: 0,
      meanRtMs: 0,
      medianRtMs: 0,
      minRtMs: 0,
      maxRtMs: 0,
    );
    expect(alertnessScore(r), 0);
  });
}
