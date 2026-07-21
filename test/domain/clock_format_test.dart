import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/clock_format.dart';

void main() {
  group('formatClock 12-hour (default)', () {
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

    test('9:30 stays 9:30 AM with no leading zero', () {
      expect(formatClock(9, 30), '9:30 AM');
    });
  });

  group('formatClock 24-hour', () {
    test('zero-pads the hour and drops AM/PM', () {
      expect(formatClock(7, 5, use24h: true), '07:05');
      expect(formatClock(9, 30, use24h: true), '09:30');
      expect(formatClock(13, 5, use24h: true), '13:05');
      expect(formatClock(23, 15, use24h: true), '23:15');
    });

    test('handles the two midnight/noon edge cases', () {
      expect(formatClock(0, 0, use24h: true), '00:00');
      expect(formatClock(12, 0, use24h: true), '12:00');
    });
  });

  group('formatClockParts', () {
    test('12-hour splits into hour, minute, and AM/PM period', () {
      expect(formatClockParts(0, 0), (hour: '12', minute: '00', period: 'AM'));
      expect(formatClockParts(12, 0), (hour: '12', minute: '00', period: 'PM'));
      expect(formatClockParts(13, 5), (hour: '1', minute: '05', period: 'PM'));
      expect(formatClockParts(9, 30), (hour: '9', minute: '30', period: 'AM'));
    });

    test('24-hour zero-pads the hour and leaves the period empty', () {
      expect(formatClockParts(0, 0, use24h: true),
          (hour: '00', minute: '00', period: ''));
      expect(formatClockParts(12, 0, use24h: true),
          (hour: '12', minute: '00', period: ''));
      expect(formatClockParts(13, 5, use24h: true),
          (hour: '13', minute: '05', period: ''));
      expect(formatClockParts(9, 30, use24h: true),
          (hour: '09', minute: '30', period: ''));
    });
  });
}
