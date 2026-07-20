import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/clock_format.dart';

void main() {
  test('formats morning, noon, and evening times', () {
    expect(formatClock(7, 5), '7:05 AM');
    expect(formatClock(7, 0), '7:00 AM');
    expect(formatClock(11, 59), '11:59 AM');
    expect(formatClock(13, 30), '1:30 PM');
    expect(formatClock(23, 15), '11:15 PM');
  });

  test('handles the two midnight/noon edge cases', () {
    expect(formatClock(0, 0), '12:00 AM');
    expect(formatClock(12, 0), '12:00 PM');
  });
}
