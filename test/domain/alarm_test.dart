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
  });
}
