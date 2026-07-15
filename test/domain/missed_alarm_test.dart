import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/missed_alarm.dart';
import 'package:rise/domain/scheduled_occurrence.dart';

void main() {
  ScheduledOccurrence occ(int id, DateTime fireAt) => ScheduledOccurrence(
        alarmId: id,
        fireAt: fireAt,
        label: 'Alarm',
        soundAsset: 'sounds/default_alarm.mp3',
        vibrate: true,
      );

  final now = DateTime.utc(2026, 7, 15, 7, 0);

  test('returns null when nothing is due', () {
    expect(findMissedAlarm(occurrences: const [], now: now), isNull);
  });

  test('finds an alarm due 10 minutes ago', () {
    final missed = occ(1, DateTime.utc(2026, 7, 15, 6, 50));
    expect(findMissedAlarm(occurrences: [missed], now: now), missed);
  });

  test('ignores an alarm due 31 minutes ago (outside the 30-minute window)', () {
    final stale = occ(1, DateTime.utc(2026, 7, 15, 6, 29));
    expect(findMissedAlarm(occurrences: [stale], now: now), isNull);
  });

  test('includes an alarm at exactly the 30-minute boundary', () {
    final edge = occ(1, DateTime.utc(2026, 7, 15, 6, 30));
    expect(findMissedAlarm(occurrences: [edge], now: now), edge);
  });

  test('ignores future alarms', () {
    final future = occ(1, DateTime.utc(2026, 7, 15, 8, 0));
    expect(findMissedAlarm(occurrences: [future], now: now), isNull);
  });

  test('returns the most recent when several were missed', () {
    final older = occ(1, DateTime.utc(2026, 7, 15, 6, 40));
    final newer = occ(2, DateTime.utc(2026, 7, 15, 6, 55));
    expect(findMissedAlarm(occurrences: [older, newer], now: now), newer);
  });

  test('respects a custom window', () {
    final missed = occ(1, DateTime.utc(2026, 7, 15, 6, 50));
    expect(
      findMissedAlarm(
          occurrences: [missed], now: now, window: const Duration(minutes: 5)),
      isNull,
    );
  });
}
