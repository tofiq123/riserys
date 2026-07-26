import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/wake_rhythm.dart';
import 'package:rise/domain/wake_event.dart';

void main() {
  DateTime d(int day) => DateTime(2026, 7, day);
  final now = DateTime(2026, 7, 20, 12); // today = Monday 20 July 2026

  /// An event on [day] ringing at [ringH]:[ringM], dismissed [after] minutes
  /// later (null = never dismissed). onTime is stamped by the real rule.
  WakeEvent ev(int day,
      {int ringH = 6, int ringM = 45, int? after, int id = 0}) {
    final ring = DateTime(2026, 7, day, ringH, ringM);
    final dismissed = after == null ? null : ring.add(Duration(minutes: after));
    return WakeEvent(
      id: id,
      alarmId: 1,
      scheduledAt: ring,
      firstRingAt: ring,
      dismissedAt: dismissed,
      onTime: after != null && after <= kOnTimeGrace.inMinutes,
    );
  }

  group('buildRhythm', () {
    test('returns exactly N local days, oldest first, ending today', () {
      final days = buildRhythm([], now, days: 14);
      expect(days, hasLength(14));
      expect(days.first.day, d(7));
      expect(days.last.day, d(20));
      for (var i = 1; i < days.length; i++) {
        expect(days[i].day.isAfter(days[i - 1].day), isTrue);
      }
    });

    test('classifies on time, late, slept through, rest day and no alarm', () {
      final days = buildRhythm(
        [
          ev(16, after: 4), // inside the 15-minute window
          ev(17, after: 40), // outside it
          ev(18, after: null), // never dismissed, and the day is past
          ev(19, after: 90), // excused below
        ],
        now,
        days: 5,
        excusedDays: {d(19)},
      );
      final byDay = {for (final r in days) r.day: r.outcome};
      expect(byDay[d(16)], RhythmOutcome.onTime);
      expect(byDay[d(17)], RhythmOutcome.late);
      expect(byDay[d(18)], RhythmOutcome.sleptThrough);
      expect(byDay[d(19)], RhythmOutcome.restDay);
      expect(byDay[d(20)], RhythmOutcome.noAlarm);
    });

    test("today's unfinished alarm is pending, never slept through", () {
      final days = buildRhythm([ev(20, after: null)], now, days: 1);
      expect(days.single.outcome, RhythmOutcome.pending);
      expect(days.single.hasAlarm, isTrue,
          reason: 'the band still draws — the alarm did ring');
    });

    test('excusing a day with no alarm stays quiet, not a spent rest day', () {
      final days = buildRhythm([], now, days: 1, excusedDays: {d(20)});
      expect(days.single.outcome, RhythmOutcome.noAlarm);
    });

    test('picks the on-time event when a day has several', () {
      final days = buildRhythm(
          [ev(20, ringH: 6, after: 90, id: 1), ev(20, ringH: 8, after: 2, id: 2)],
          now,
          days: 1);
      expect(days.single.outcome, RhythmOutcome.onTime);
      expect(days.single.ringMinute, 8 * 60 + 45,
          reason: 'the on-time event supplies the band, not the earlier miss');
    });

    test('the on-time band is exactly the grace window', () {
      final r = buildRhythm([ev(20, ringH: 6, ringM: 45, after: 4)], now,
              days: 1)
          .single;
      expect(r.ringMinute, 6 * 60 + 45);
      expect(r.graceEndMinute, 6 * 60 + 45 + kOnTimeGrace.inMinutes);
      expect(r.wokeMinute! <= r.graceEndMinute!, isTrue,
          reason: 'an on-time mark must sit inside the band it is drawn against');
    });

    test('a late mark sits above the band, by lateBy minutes', () {
      final r = buildRhythm([ev(20, ringH: 6, ringM: 0, after: 40)], now,
              days: 1)
          .single;
      expect(r.outcome, RhythmOutcome.late);
      expect(r.lateBy, 40 - kOnTimeGrace.inMinutes);
    });

    test('a dismissal past midnight keeps counting up, never wraps', () {
      // Rings 23:55, dismissed 00:10 the next calendar day.
      final r = buildRhythm([ev(19, ringH: 23, ringM: 55, after: 15)], now,
              days: 2)
          .first;
      expect(r.ringMinute, 23 * 60 + 55);
      expect(r.wokeMinute, 24 * 60 + 10,
          reason: 'minutes are counted from THIS day\'s midnight');
      expect(r.wokeMinute! > r.ringMinute!, isTrue);
    });

    test('freezeAbsorbed marks the day without softening its outcome', () {
      final r = buildRhythm([ev(19, after: 60)], now,
              days: 2, freezeAbsorbed: {d(19)})
          .first;
      expect(r.outcome, RhythmOutcome.late, reason: 'still honestly late');
      expect(r.freezeAbsorbed, isTrue);
    });
  });

  group('buildRhythmWeeks', () {
    test('always starts on a Monday so the grid needs no leading blanks', () {
      for (var day = 20; day <= 26; day++) {
        final days =
            buildRhythmWeeks([], DateTime(2026, 7, day, 12), weeks: 5);
        expect(days.first.day.weekday, DateTime.monday,
            reason: 'today = ${DateTime(2026, 7, day).weekday}');
        expect(days.last.day, DateTime(2026, 7, day));
      }
    });

    test('spans five weeks of rows', () {
      // Sunday 26 July 2026 → a full 5x7 grid.
      final days = buildRhythmWeeks([], DateTime(2026, 7, 26, 12), weeks: 5);
      expect(days, hasLength(35));
    });

    test('a mid-week today gives a short last row, not a wrong one', () {
      // Wednesday 22 July 2026 → 4 full weeks + 3 days.
      final days = buildRhythmWeeks([], DateTime(2026, 7, 22, 12), weeks: 5);
      expect(days, hasLength(28 + 3));
      expect(days.last.day.weekday, DateTime.wednesday);
    });
  });

  group('rhythmRange', () {
    test('covers every ring, window top and wake', () {
      final days = buildRhythm(
          [ev(19, ringH: 6, ringM: 0, after: 5), ev(20, ringH: 7, ringM: 30, after: 60)],
          now,
          days: 2);
      final r = rhythmRange(days);
      expect(r.lo, lessThanOrEqualTo(6 * 60));
      expect(r.hi, greaterThanOrEqualTo(8 * 60 + 30));
    });

    test('never spans less than 90 minutes', () {
      final days = buildRhythm(
          [for (var i = 14; i <= 20; i++) ev(i, ringH: 6, ringM: 45, after: 3)],
          now,
          days: 7);
      final r = rhythmRange(days);
      expect(r.hi - r.lo, greaterThanOrEqualTo(90));
    });

    test('snaps to quarter hours', () {
      final days = buildRhythm([ev(20, ringH: 6, ringM: 7, after: 3)], now,
          days: 1);
      final r = rhythmRange(days);
      expect(r.lo % 15, 0);
      expect(r.hi % 15, 0);
    });

    test('an empty window falls back to a plain morning', () {
      final r = rhythmRange(buildRhythm([], now, days: 14));
      expect(r.lo, 5 * 60);
      expect(r.hi, 9 * 60);
    });
  });

  group('summaries', () {
    test('counts only days that had an alarm and a settled outcome', () {
      final days = buildRhythm(
        [
          ev(16, after: 3), // on time
          ev(17, after: 3), // on time
          ev(18, after: 40), // late
          ev(19, after: 3), // excused → rest day, excluded
          ev(20, after: null), // today, pending, excluded
        ],
        now,
        days: 6, // includes 15 July with no alarm at all
        excusedDays: {d(19)},
      );
      expect(settledDays(days), hasLength(3));
      expect(rhythmSummary(days),
          'Up within 15 minutes of your alarm on 2 of 3 mornings.');
    });

    test('an empty window says so instead of dividing by zero', () {
      expect(rhythmSummary(buildRhythm([], now, days: 14)),
          'No mornings logged in this window yet.');
    });

    test('the tally line lists only what actually happened', () {
      final days = buildRhythm(
          [ev(18, after: 3), ev(19, after: 40)], now, days: 4);
      expect(rhythmTallyLine(days), '1 on time · 1 late');
    });

    test('a nothing-logged month reads as a sentence, not an empty string', () {
      expect(rhythmTallyLine(buildRhythm([], now, days: 35)),
          'Nothing logged in these weeks yet.');
    });

    test('tally counts every class', () {
      final days = buildRhythm(
        [ev(16, after: 3), ev(17, after: 40), ev(18, after: null), ev(19, after: 3)],
        now,
        days: 6,
        excusedDays: {d(19)},
      );
      final t = rhythmTally(days);
      expect(t.onTime, 1);
      expect(t.late, 1);
      expect(t.slept, 1);
      expect(t.rest, 1);
      expect(t.none, 2); // 15 and 20 July
    });
  });
}
