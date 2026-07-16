import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/notification_request.dart';

void main() {
  test('holds its fields', () {
    const r = NotificationRequest(
      alarmId: 3,
      fireAtEpochMs: 1784276400000,
      label: 'Run',
      sound: 'default_alarm.wav',
      burstIndex: 0,
      burstTotal: 16,
    );
    expect(r.alarmId, 3);
    expect(r.fireAtEpochMs, 1784276400000);
    expect(r.label, 'Run');
    expect(r.sound, 'default_alarm.wav');
    expect(r.burstIndex, 0);
    expect(r.burstTotal, 16);
  });

  test('is the primary notification when burstIndex is 0', () {
    const primary = NotificationRequest(
        alarmId: 1, fireAtEpochMs: 0, label: 'a', sound: 's', burstIndex: 0, burstTotal: 4);
    const followUp = NotificationRequest(
        alarmId: 1, fireAtEpochMs: 0, label: 'a', sound: 's', burstIndex: 1, burstTotal: 4);
    expect(primary.isPrimary, isTrue);
    expect(followUp.isPrimary, isFalse);
  });

  test('value equality', () {
    const a = NotificationRequest(
        alarmId: 1, fireAtEpochMs: 10, label: 'x', sound: 's', burstIndex: 0, burstTotal: 1);
    const b = NotificationRequest(
        alarmId: 1, fireAtEpochMs: 10, label: 'x', sound: 's', burstIndex: 0, burstTotal: 1);
    const c = NotificationRequest(
        alarmId: 1, fireAtEpochMs: 20, label: 'x', sound: 's', burstIndex: 0, burstTotal: 1);
    expect(a, equals(b));
    expect(a, isNot(equals(c)));
    expect(a.hashCode, b.hashCode);
  });
}
