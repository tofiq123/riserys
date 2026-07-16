import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:rise/domain/alarm.dart';
import 'package:rise/domain/reconcile.dart';
import 'package:rise/domain/scheduled_occurrence.dart';

void main() {
  late tz.Location ny;

  setUpAll(() {
    tzdata.initializeTimeZones();
    ny = tz.getLocation('America/New_York');
  });

  ScheduledOccurrence occ(int id, DateTime fireAt) => ScheduledOccurrence(
        alarmId: id,
        fireAt: fireAt,
        label: 'Alarm',
        soundAsset: 'sounds/default_alarm.mp3',
        vibrate: true,
      );

  group('desiredOccurrences', () {
    test('skips disabled alarms', () {
      final now = tz.TZDateTime(ny, 2026, 7, 15, 5, 0);
      final result = desiredOccurrences(
        alarms: const [
          Alarm(id: 1, hour: 6, minute: 30),
          Alarm(id: 2, hour: 7, minute: 0, enabled: false),
        ],
        now: now,
        location: ny,
      );
      expect(result.map((o) => o.alarmId), [1]);
    });

    test('is sorted by fire time', () {
      final now = tz.TZDateTime(ny, 2026, 7, 15, 5, 0);
      final result = desiredOccurrences(
        alarms: const [
          Alarm(id: 1, hour: 9, minute: 0),
          Alarm(id: 2, hour: 6, minute: 30),
        ],
        now: now,
        location: ny,
      );
      expect(result.map((o) => o.alarmId), [2, 1]);
    });

    test('carries label, sound and vibrate through', () {
      final now = tz.TZDateTime(ny, 2026, 7, 15, 5, 0);
      final result = desiredOccurrences(
        alarms: const [
          Alarm(id: 1, hour: 6, minute: 30, label: 'Run', soundAsset: 'sounds/x.mp3', vibrate: false),
        ],
        now: now,
        location: ny,
      );
      expect(result.single.label, 'Run');
      expect(result.single.soundAsset, 'sounds/x.mp3');
      expect(result.single.vibrate, isFalse);
    });

    test('emits fireAt in UTC', () {
      final now = tz.TZDateTime(ny, 2026, 7, 15, 5, 0);
      final result = desiredOccurrences(
        alarms: const [Alarm(id: 1, hour: 6, minute: 30)],
        now: now,
        location: ny,
      );
      expect(result.single.fireAt.isUtc, isTrue);
    });

    test(
        'breaks ties on alarmId when two alarms fire at the exact same '
        'instant, so ordering is deterministic rather than an artifact of '
        "List.sort's (unspecified, non-stable) tie handling", () {
      final now = tz.TZDateTime(ny, 2026, 7, 15, 5, 0);
      // Listed with the higher id first, on purpose: this only proves the
      // tie-breaker exists if the output order does not just mirror input
      // order.
      final result = desiredOccurrences(
        alarms: const [
          Alarm(id: 3, hour: 6, minute: 30),
          Alarm(id: 2, hour: 6, minute: 30),
        ],
        now: now,
        location: ny,
      );
      expect(result.map((o) => o.alarmId), [2, 3]);
    });
  });

  group('diffSchedule', () {
    test('schedules everything when nothing is currently scheduled', () {
      final desired = [occ(1, DateTime.utc(2026, 7, 15, 10, 30))];
      final plan = diffSchedule(desired: desired, current: const []);
      expect(plan.toSchedule, desired);
      expect(plan.toCancel, isEmpty);
    });

    test('is idempotent: diffing identical lists produces an empty plan', () {
      // desired and current are independently constructed but have identical field values.
      // This exercises ScheduledOccurrence.== to verify value-based equality, not identity.
      final desired = [
        occ(1, DateTime.utc(2026, 7, 15, 10, 30)),
        occ(2, DateTime.utc(2026, 7, 15, 11, 0)),
      ];
      final current = [
        occ(1, DateTime.utc(2026, 7, 15, 10, 30)),
        occ(2, DateTime.utc(2026, 7, 15, 11, 0)),
      ];
      final plan = diffSchedule(desired: desired, current: current);
      expect(plan.isEmpty, isTrue);
    });

    test('cancels occurrences that are no longer desired', () {
      final plan = diffSchedule(
        desired: const [],
        current: [occ(1, DateTime.utc(2026, 7, 15, 10, 30))],
      );
      expect(plan.toCancel, [1]);
      expect(plan.toSchedule, isEmpty);
    });

    test('reschedules an alarm whose fire time changed', () {
      final plan = diffSchedule(
        desired: [occ(1, DateTime.utc(2026, 7, 15, 11, 30))],
        current: [occ(1, DateTime.utc(2026, 7, 15, 10, 30))],
      );
      expect(plan.toSchedule.single.fireAt, DateTime.utc(2026, 7, 15, 11, 30));
      expect(plan.toCancel, isEmpty,
          reason: 'rescheduling the same id replaces it; no cancel needed');
    });

    test('reschedules when only the sound changed', () {
      final current = [occ(1, DateTime.utc(2026, 7, 15, 10, 30))];
      final desired = [
        ScheduledOccurrence(
          alarmId: 1,
          fireAt: DateTime.utc(2026, 7, 15, 10, 30),
          label: 'Alarm',
          soundAsset: 'sounds/birdsong.mp3',
          vibrate: true,
        )
      ];
      final plan = diffSchedule(desired: desired, current: current);
      expect(plan.toSchedule, desired);
    });

    test('handles a mixed add, change and remove in one plan', () {
      final plan = diffSchedule(
        desired: [
          occ(1, DateTime.utc(2026, 7, 15, 11, 30)), // changed
          occ(3, DateTime.utc(2026, 7, 15, 12, 0)), // added
        ],
        current: [
          occ(1, DateTime.utc(2026, 7, 15, 10, 30)),
          occ(2, DateTime.utc(2026, 7, 15, 9, 0)), // removed
        ],
      );
      expect(plan.toSchedule.map((o) => o.alarmId).toSet(), {1, 3});
      expect(plan.toCancel, [2]);
    });
  });

  group('ScheduledOccurrence', () {
    test('two independently constructed occurrences with identical fields are == and hash equally', () {
      final a = occ(1, DateTime.utc(2026, 7, 15, 10, 30));
      final b = occ(1, DateTime.utc(2026, 7, 15, 10, 30));

      // Verify they are different object instances
      expect(identical(a, b), isFalse);

      // Verify value-based equality
      expect(a == b, isTrue);

      // Verify equal objects have equal hash codes (contract required for set/map use)
      expect(a.hashCode == b.hashCode, isTrue);
    });
  });
}
