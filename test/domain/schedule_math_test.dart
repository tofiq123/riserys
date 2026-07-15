import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:rise/domain/alarm.dart';
import 'package:rise/domain/schedule_math.dart';

void main() {
  late tz.Location ny;
  late tz.Location utc;

  setUpAll(() {
    tzdata.initializeTimeZones();
    ny = tz.getLocation('America/New_York');
    utc = tz.getLocation('UTC');
  });

  group('weekdayToIndex', () {
    test('maps Dart Monday=1 to index 1 and Sunday=7 to index 0', () {
      expect(weekdayToIndex(DateTime.monday), 1);
      expect(weekdayToIndex(DateTime.saturday), 6);
      expect(weekdayToIndex(DateTime.sunday), 0);
    });
  });

  group('one-shot alarms', () {
    test('fires later today when the time has not passed', () {
      const alarm = Alarm(id: 1, hour: 6, minute: 30);
      final from = tz.TZDateTime(ny, 2026, 7, 15, 5, 0);
      final next = nextOccurrence(alarm: alarm, from: from, location: ny);
      expect(next, tz.TZDateTime(ny, 2026, 7, 15, 6, 30));
    });

    test('rolls to tomorrow when the time has passed', () {
      const alarm = Alarm(id: 1, hour: 6, minute: 30);
      final from = tz.TZDateTime(ny, 2026, 7, 15, 7, 0);
      final next = nextOccurrence(alarm: alarm, from: from, location: ny);
      expect(next, tz.TZDateTime(ny, 2026, 7, 16, 6, 30));
    });

    test('rolls to tomorrow when exactly at the alarm time (strictly after)', () {
      const alarm = Alarm(id: 1, hour: 6, minute: 30);
      final from = tz.TZDateTime(ny, 2026, 7, 15, 6, 30);
      final next = nextOccurrence(alarm: alarm, from: from, location: ny);
      expect(next, tz.TZDateTime(ny, 2026, 7, 16, 6, 30));
    });
  });

  group('disabled alarms', () {
    test('return null', () {
      const alarm = Alarm(id: 1, hour: 6, minute: 30, enabled: false);
      final from = tz.TZDateTime(ny, 2026, 7, 15, 5, 0);
      expect(nextOccurrence(alarm: alarm, from: from, location: ny), isNull);
    });
  });

  group('repeating alarms', () {
    test('weekday alarm on Saturday rolls to Monday', () {
      // 2026-07-18 is a Saturday. Weekdays = Mon..Fri.
      const alarm = Alarm(id: 1, hour: 6, minute: 30, days: {1, 2, 3, 4, 5});
      final from = tz.TZDateTime(ny, 2026, 7, 18, 9, 0);
      final next = nextOccurrence(alarm: alarm, from: from, location: ny);
      expect(next, tz.TZDateTime(ny, 2026, 7, 20, 6, 30)); // Monday
    });

    test('fires today when today is a selected day and time has not passed', () {
      // 2026-07-15 is a Wednesday (index 3).
      const alarm = Alarm(id: 1, hour: 6, minute: 30, days: {3});
      final from = tz.TZDateTime(ny, 2026, 7, 15, 5, 0);
      final next = nextOccurrence(alarm: alarm, from: from, location: ny);
      expect(next, tz.TZDateTime(ny, 2026, 7, 15, 6, 30));
    });

    test('single-day alarm rolls a full week when today has passed', () {
      const alarm = Alarm(id: 1, hour: 6, minute: 30, days: {3}); // Wednesday
      final from = tz.TZDateTime(ny, 2026, 7, 15, 7, 0);
      final next = nextOccurrence(alarm: alarm, from: from, location: ny);
      expect(next, tz.TZDateTime(ny, 2026, 7, 22, 6, 30));
    });

    test('Sunday-only alarm uses index 0', () {
      // 2026-07-19 is a Sunday.
      const alarm = Alarm(id: 1, hour: 8, minute: 0, days: {0});
      final from = tz.TZDateTime(ny, 2026, 7, 15, 12, 0);
      final next = nextOccurrence(alarm: alarm, from: from, location: ny);
      expect(next, tz.TZDateTime(ny, 2026, 7, 19, 8, 0));
    });
  });

  group('DST spring-forward (2026-03-08 America/New_York, 02:00 -> 03:00)', () {
    test('02:30 does not exist and fires at the first valid instant after', () {
      const alarm = Alarm(id: 1, hour: 2, minute: 30);
      final from = tz.TZDateTime(ny, 2026, 3, 7, 22, 0);
      final next = nextOccurrence(alarm: alarm, from: from, location: ny)!;
      expect(next, tz.TZDateTime(ny, 2026, 3, 8, 3, 0));
      expect(next.timeZoneOffset, const Duration(hours: -4)); // EDT
    });

    test('01:30 still exists on the transition day', () {
      const alarm = Alarm(id: 1, hour: 1, minute: 30);
      final from = tz.TZDateTime(ny, 2026, 3, 7, 22, 0);
      final next = nextOccurrence(alarm: alarm, from: from, location: ny);
      expect(next, tz.TZDateTime(ny, 2026, 3, 8, 1, 30));
    });

    test('a daily alarm crossing the transition keeps its wall-clock time', () {
      const alarm = Alarm(id: 1, hour: 6, minute: 30, days: {0, 1, 2, 3, 4, 5, 6});
      final from = tz.TZDateTime(ny, 2026, 3, 7, 12, 0);
      final next = nextOccurrence(alarm: alarm, from: from, location: ny)!;
      expect(next.hour, 6);
      expect(next.minute, 30);
      expect(next.day, 8);
    });
  });

  group('DST fall-back (2026-11-01 America/New_York, 02:00 -> 01:00)', () {
    test('the duplicated 01:30 fires exactly once, then next day', () {
      const alarm = Alarm(id: 1, hour: 1, minute: 30, days: {0, 1, 2, 3, 4, 5, 6});
      final from = tz.TZDateTime(ny, 2026, 10, 31, 12, 0);

      final first = nextOccurrence(alarm: alarm, from: from, location: ny)!;
      expect(first.year, 2026);
      expect(first.month, 11);
      expect(first.day, 1);
      expect(first.hour, 1);
      expect(first.minute, 30);

      // The next occurrence after the first must be the NEXT DAY, never the
      // second (EST) 01:30 on the same date.
      final second = nextOccurrence(alarm: alarm, from: first, location: ny)!;
      expect(second.day, 2);
      expect(second.hour, 1);
      expect(second.minute, 30);
    });
  });

  group('timezone independence', () {
    test('the same alarm resolves to different instants in different zones', () {
      const alarm = Alarm(id: 1, hour: 6, minute: 30);
      final fromNy = tz.TZDateTime(ny, 2026, 7, 15, 5, 0);
      final fromUtc = tz.TZDateTime(utc, 2026, 7, 15, 5, 0);
      final nextNy = nextOccurrence(alarm: alarm, from: fromNy, location: ny)!;
      final nextUtc = nextOccurrence(alarm: alarm, from: fromUtc, location: utc)!;
      expect(nextNy.hour, 6);
      expect(nextUtc.hour, 6);
      expect(nextNy.toUtc(), isNot(equals(nextUtc.toUtc())));
    });
  });

  group('resolveWallTime', () {
    test('returns the requested wall time when it exists', () {
      final t = resolveWallTime(ny, 2026, 7, 15, 6, 30);
      expect(t.hour, 6);
      expect(t.minute, 30);
    });

    test('snaps a nonexistent DST-gap time forward to the gap end', () {
      final t = resolveWallTime(ny, 2026, 3, 8, 2, 30);
      expect(t.hour, 3);
      expect(t.minute, 0);
    });
  });
}
