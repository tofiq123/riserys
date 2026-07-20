import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/alarm.dart';

void main() {
  group('Alarm 12/24 hour conversion', () {
    test('midnight is 12 AM', () {
      const a = Alarm(id: 1, hour: 0, minute: 0);
      expect(a.hour12, 12);
      expect(a.isAm, isTrue);
    });

    test('noon is 12 PM', () {
      const a = Alarm(id: 1, hour: 12, minute: 0);
      expect(a.hour12, 12);
      expect(a.isAm, isFalse);
    });

    test('13:30 is 1:30 PM', () {
      const a = Alarm(id: 1, hour: 13, minute: 30);
      expect(a.hour12, 1);
      expect(a.isAm, isFalse);
    });

    test('to24Hour maps 12 AM to 0 and 12 PM to 12', () {
      expect(Alarm.to24Hour(12, true), 0);
      expect(Alarm.to24Hour(12, false), 12);
      expect(Alarm.to24Hour(6, true), 6);
      expect(Alarm.to24Hour(6, false), 18);
    });
  });

  group('Alarm defaults and copyWith', () {
    test('defaults to a one-shot enabled alarm', () {
      const a = Alarm(id: 1, hour: 6, minute: 30);
      expect(a.days, isEmpty);
      expect(a.enabled, isTrue);
      expect(a.vibrate, isTrue);
    });

    test('copyWith replaces only named fields', () {
      const a = Alarm(id: 1, hour: 6, minute: 30, label: 'Run');
      final b = a.copyWith(hour: 7);
      expect(b.hour, 7);
      expect(b.minute, 30);
      expect(b.label, 'Run');
      expect(b.id, 1);
    });

    test('equal field values compare equal', () {
      const a = Alarm(id: 1, hour: 6, minute: 30, days: {1, 2});
      const b = Alarm(id: 1, hour: 6, minute: 30, days: {1, 2});
      expect(a, equals(b));
    });

    test('mission fields default to none/easy and round-trip through copyWith', () {
      const a = Alarm(id: 1, hour: 6, minute: 30);
      expect(a.mission, 'none');
      expect(a.missionDiff, 'easy');
      final b = a.copyWith(mission: 'math', missionDiff: 'hard');
      expect(b.mission, 'math');
      expect(b.missionDiff, 'hard');
      expect(b.minute, 30); // unrelated field preserved
      expect(a == a.copyWith(), isTrue); // equality includes the new fields
    });

    test('missionCount defaults to 1 and round-trips through copyWith/equality', () {
      const a = Alarm(id: 1, hour: 6, minute: 30);
      expect(a.missionCount, 1);
      final b = a.copyWith(missionCount: 3);
      expect(b.missionCount, 3);
      expect(b.hour, 6); // unrelated field preserved
      expect(a == b, isFalse); // equality includes missionCount
      expect(a.hashCode == b.hashCode, isFalse);
    });
  });

  group('Alarm snoozedUntil', () {
    test('snoozedUntil round-trips and clears via the sentinel', () {
      const a = Alarm(id: 1, hour: 6, minute: 30);
      expect(a.snoozedUntil, isNull);
      final snoozed = a.copyWith(snoozedUntil: DateTime.utc(2026, 7, 20, 6, 39));
      expect(snoozed.snoozedUntil, DateTime.utc(2026, 7, 20, 6, 39));
      // Sentinel clears it back to null (plain copyWith can't express "set null").
      expect(snoozed.copyWith(clearSnoozedUntil: true).snoozedUntil, isNull);
      // copyWith without the flag preserves it.
      expect(snoozed.copyWith(label: 'x').snoozedUntil, DateTime.utc(2026, 7, 20, 6, 39));
    });

    test('equality treats the same snooze instant across UTC/local as equal', () {
      final a = const Alarm(id: 1, hour: 6, minute: 30)
          .copyWith(snoozedUntil: DateTime.utc(2026, 7, 20, 6, 39));
      final b = const Alarm(id: 1, hour: 6, minute: 30)
          .copyWith(snoozedUntil: DateTime.utc(2026, 7, 20, 6, 39).toLocal());
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });
}
