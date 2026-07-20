import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/phq2.dart';

void main() {
  test('the two verbatim PHQ-2 items and four options are present', () {
    expect(phq2Questions, hasLength(2));
    expect(phq2Questions[0], contains('little interest or pleasure'));
    expect(phq2Questions[1], contains('down, depressed, or hopeless'));
    expect(phq2Answers, [
      'Not at all',
      'Several days',
      'More than half the days',
      'Nearly every day',
    ]);
  });

  test('phq2Score sums the two answers (0..6)', () {
    expect(phq2Score([0, 0]), 0);
    expect(phq2Score([1, 2]), 3);
    expect(phq2Score([3, 3]), 6);
    expect(phq2Score([0, 3]), 3);
  });

  test('phq2Score clamps out-of-range values defensively', () {
    expect(phq2Score([5, -1]), 3); // 3 + 0
    expect(phq2Score([9, 9]), 6);
  });

  test('isAbovePhq2Threshold uses the standard cut point of 3', () {
    expect(phq2Threshold, 3);
    expect(isAbovePhq2Threshold(0), isFalse);
    expect(isAbovePhq2Threshold(2), isFalse);
    expect(isAbovePhq2Threshold(3), isTrue); // exactly at the cut point
    expect(isAbovePhq2Threshold(6), isTrue);
  });
}
