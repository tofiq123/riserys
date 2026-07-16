import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/notification_budget.dart';
import 'package:rise/domain/notification_request.dart';
import 'package:rise/domain/scheduled_occurrence.dart';

void main() {
  final now = DateTime.utc(2026, 7, 16, 12, 0, 0);

  ScheduledOccurrence occ(int id, int minutesFromNow) => ScheduledOccurrence(
        alarmId: id,
        fireAt: now.add(Duration(minutes: minutesFromNow)),
        label: 'Alarm $id',
        soundAsset: 'default_alarm.wav',
        vibrate: true,
      );

  group('single alarm', () {
    test('gets a full burst of perAlarmMax notifications', () {
      final out = allocateNotifications(occurrences: [occ(1, 5)], now: now);
      expect(out, hasLength(16));
      expect(out.every((n) => n.alarmId == 1), isTrue);
      expect(out.map((n) => n.burstIndex).toList(), List.generate(16, (i) => i));
      expect(out.every((n) => n.burstTotal == 16), isTrue);
    });

    test('spaces the burst 30 s apart starting at the fire time', () {
      final out = allocateNotifications(occurrences: [occ(1, 5)], now: now);
      final base = now.add(const Duration(minutes: 5)).millisecondsSinceEpoch;
      expect(out[0].fireAtEpochMs, base);
      expect(out[1].fireAtEpochMs, base + 30000);
      expect(out[15].fireAtEpochMs, base + 15 * 30000);
    });
  });

  group('budget distribution', () {
    test('five alarms stay within the 64 cap, soonest fullest', () {
      final out = allocateNotifications(
        occurrences: [occ(1, 5), occ(2, 60), occ(3, 120), occ(4, 180), occ(5, 240)],
        now: now,
      );
      expect(out.length, lessThanOrEqualTo(64));
      int countFor(int id) => out.where((n) => n.alarmId == id).length;
      // Every alarm fires at least once; soonest is non-increasing.
      for (final id in [1, 2, 3, 4, 5]) {
        expect(countFor(id), greaterThanOrEqualTo(1), reason: 'alarm $id must fire');
      }
      expect(countFor(1), 16);
      expect(countFor(1) >= countFor(2), isTrue);
      expect(countFor(2) >= countFor(3), isTrue);
    });

    test('never exceeds the cap even with many alarms', () {
      final many = List.generate(20, (i) => occ(i + 1, (i + 1) * 10));
      final out = allocateNotifications(occurrences: many, now: now);
      expect(out.length, lessThanOrEqualTo(64));
    });

    test('when alarms exceed the cap, only the soonest cap alarms fire', () {
      final many = List.generate(70, (i) => occ(i + 1, i + 1));
      final out = allocateNotifications(occurrences: many, now: now);
      expect(out.length, lessThanOrEqualTo(64));
      final firingIds = out.map((n) => n.alarmId).toSet();
      expect(firingIds, hasLength(64));
      // The soonest 64 (ids 1..64) fire; the farthest 6 (65..70) are dropped.
      expect(firingIds.contains(1), isTrue);
      expect(firingIds.contains(70), isFalse);
      expect(droppedAlarmCount(occurrences: many, now: now), 6);
    });
  });

  group('filtering and ordering', () {
    test('ignores past occurrences', () {
      final out = allocateNotifications(occurrences: [occ(1, -5)], now: now);
      expect(out, isEmpty);
    });

    test('no alarms yields no notifications', () {
      expect(allocateNotifications(occurrences: const [], now: now), isEmpty);
    });

    test('output is sorted by fire time', () {
      final out = allocateNotifications(
        occurrences: [occ(1, 5), occ(2, 60)],
        now: now,
      );
      for (var i = 1; i < out.length; i++) {
        expect(out[i].fireAtEpochMs, greaterThanOrEqualTo(out[i - 1].fireAtEpochMs));
      }
    });

    test('carries the alarm sound and label', () {
      final out = allocateNotifications(
        occurrences: [
          ScheduledOccurrence(
            alarmId: 9,
            fireAt: now.add(const Duration(minutes: 5)),
            label: 'Gym',
            soundAsset: 'birdsong.wav',
            vibrate: true,
          )
        ],
        now: now,
      );
      expect(out.first.label, 'Gym');
      expect(out.first.sound, 'birdsong.wav');
    });

    test('respects a reduced cap (other notification types reserve slots)', () {
      final out = allocateNotifications(occurrences: [occ(1, 5)], now: now, cap: 4);
      expect(out, hasLength(4));
    });
  });
}
