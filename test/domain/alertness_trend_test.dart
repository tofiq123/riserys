import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/alertness_trend.dart';

void main() {
  test('insufficient below the minimum score count', () {
    expect(alertnessTrendOf([50, 60, 70]), AlertnessTrend.insufficient);
    expect(alertnessTrendOf(const []), AlertnessTrend.insufficient);
  });

  test('rising when the recent half clearly beats the earlier half', () {
    expect(alertnessTrendOf([40, 45, 70, 75]), AlertnessTrend.rising);
  });

  test('easing when the recent half clearly trails the earlier half', () {
    expect(alertnessTrendOf([80, 78, 55, 52]), AlertnessTrend.easing);
  });

  test('steady when the two halves are within the threshold', () {
    expect(alertnessTrendOf([70, 72, 71, 73]), AlertnessTrend.steady);
  });

  test('odd counts drop the middle sample from both halves', () {
    // half = 2: earlier [50,52], recent [88,90]; middle 60 ignored -> rising.
    expect(alertnessTrendOf([50, 52, 60, 88, 90]), AlertnessTrend.rising);
  });

  test('threshold is configurable', () {
    // delta of exactly 5 is rising at the default threshold...
    expect(alertnessTrendOf([60, 60, 65, 65]), AlertnessTrend.rising);
    // ...but steady when the bar is raised.
    expect(alertnessTrendOf([60, 60, 65, 65], thresholdPoints: 6),
        AlertnessTrend.steady);
  });
}
