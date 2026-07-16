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

    test('carries the recurrence pattern (hour, minute, weekdays) from Alarm '
        'through to the occurrence — a refactor that silently flips or drops '
        'a weekday must fail here, not just in a doc comment', () {
      final now = tz.TZDateTime(ny, 2026, 7, 15, 5, 0);
      final result = desiredOccurrences(
        alarms: const [
          Alarm(id: 1, hour: 6, minute: 30, days: {0, 6}),
        ],
        now: now,
        location: ny,
      );
      expect(result.single.hour, 6);
      expect(result.single.minute, 30);
      expect(result.single.weekdays, {0, 6});
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
