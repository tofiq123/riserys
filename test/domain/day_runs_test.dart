import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/day_runs.dart';

DateTime d(int day) => DateTime(2026, 3, day);

void main() {
  group('daysBetween', () {
    test('counts whole calendar days regardless of time-of-day', () {
      expect(daysBetween(DateTime(2026, 3, 1, 23), DateTime(2026, 3, 2, 1)), 1);
      expect(daysBetween(DateTime(2026, 3, 1), DateTime(2026, 3, 1)), 0);
      expect(daysBetween(DateTime(2026, 3, 5), DateTime(2026, 3, 1)), -4);
    });

    test('is stable across a spring-forward DST boundary', () {
      // Many DST regions spring forward on 2026-03-08; the "short" 23-hour day
      // must still read as exactly one calendar day apart.
      expect(daysBetween(DateTime(2026, 3, 8), DateTime(2026, 3, 9)), 1);
    });
  });

  group('longestConsecutiveRun', () {
    test('empty input is 0', () {
      expect(longestConsecutiveRun(const []), 0);
    });

    test('isolated days each count as a run of 1', () {
      expect(longestConsecutiveRun([d(1), d(5), d(20)]), 1);
    });

    test('finds the longest consecutive block', () {
      // 1,2,3 then gap, then 10,11.
      expect(longestConsecutiveRun([d(2), d(1), d(3), d(10), d(11)]), 3);
    });

    test('duplicate days collapse and do not inflate the run', () {
      expect(longestConsecutiveRun([d(1), d(1), d(2), d(2), d(2)]), 2);
    });

    test('ignores the time component when grouping', () {
      final days = [
        DateTime(2026, 3, 1, 6, 30),
        DateTime(2026, 3, 2, 23, 5),
        DateTime(2026, 3, 3, 0, 1),
      ];
      expect(longestConsecutiveRun(days), 3);
    });

    test('spans month and year boundaries', () {
      expect(
        longestConsecutiveRun([
          DateTime(2026, 12, 30),
          DateTime(2026, 12, 31),
          DateTime(2027, 1, 1),
        ]),
        3,
      );
    });
  });
}
