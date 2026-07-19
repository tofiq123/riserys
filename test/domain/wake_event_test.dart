import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/wake_event.dart';

void main() {
  final ring = DateTime.utc(2026, 7, 17, 6, 0);

  test('isOpen is true until dismissed', () {
    final e = WakeEvent(id: 1, alarmId: 2, scheduledAt: ring, firstRingAt: ring);
    expect(e.isOpen, isTrue);
    expect(e.copyWith(dismissedAt: ring.add(const Duration(minutes: 3))).isOpen, isFalse);
  });

  test('timeToWake is dismissedAt minus scheduledAt, or null when open', () {
    final e = WakeEvent(id: 1, alarmId: 2, scheduledAt: ring, firstRingAt: ring);
    expect(e.timeToWake, isNull);
    final done = e.copyWith(dismissedAt: ring.add(const Duration(minutes: 4)));
    expect(done.timeToWake, const Duration(minutes: 4));
  });

  test('localDay is the local-midnight of firstRingAt', () {
    final e = WakeEvent(id: 1, alarmId: 2, scheduledAt: ring, firstRingAt: ring);
    final l = ring.toLocal();
    expect(e.localDay, DateTime(l.year, l.month, l.day));
    expect(e.localDay.hour, 0);
  });

  test('equality treats the same instant across UTC/local as equal', () {
    final a = WakeEvent(id: 1, alarmId: 2, scheduledAt: ring, firstRingAt: ring,
        dismissedAt: ring.add(const Duration(minutes: 3)));
    final b = a.copyWith(dismissedAt: ring.add(const Duration(minutes: 3)).toLocal());
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('alertnessScore defaults to null and round-trips through copyWith', () {
    final e = WakeEvent(id: 1, alarmId: 2, scheduledAt: ring, firstRingAt: ring);
    expect(e.alertnessScore, isNull);
    final scored = e.copyWith(alertnessScore: 84);
    expect(scored.alertnessScore, 84);
  });

  test('alertnessScore participates in equality and hashCode', () {
    final base = WakeEvent(id: 1, alarmId: 2, scheduledAt: ring, firstRingAt: ring);
    final a = base.copyWith(alertnessScore: 84);
    final b = base.copyWith(alertnessScore: 84);
    final c = base.copyWith(alertnessScore: 50);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(c));
    expect(a, isNot(base)); // null vs 84 differ
  });
}
