import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/rise_settings.dart';

void main() {
  test('defaults', () {
    const s = RiseSettings();
    expect(s.snoozeMaxCount, 3);
    expect(s.snoozeFlatMinutes, 0);
    expect(s.wakeCheckEnabled, isTrue);
    expect(s.wakeCheckDelayMinutes, 5);
    expect(s.wakeIntention, '');
    expect(s.targetWakeHour, isNull);
    expect(s.targetWakeMinute, isNull);
    expect(s.hasTargetWake, isFalse);
    expect(s.adaptiveMissions, isFalse);
  });

  test('adaptiveMissions copyWith and equality', () {
    const s = RiseSettings();
    expect(s.copyWith(adaptiveMissions: true).adaptiveMissions, isTrue);
    expect(const RiseSettings(adaptiveMissions: true) == const RiseSettings(),
        isFalse);
    expect(
        const RiseSettings(adaptiveMissions: true).hashCode ==
            const RiseSettings().hashCode,
        isFalse);
    // Unrelated copyWith preserves it.
    expect(const RiseSettings(adaptiveMissions: true).copyWith(snoozeMaxCount: 2)
        .adaptiveMissions, isTrue);
  });

  test('snoozeDurationMinutes uses the shrinking schedule by default', () {
    const s = RiseSettings();
    expect(s.snoozeDurationMinutes(0), 9);
    expect(s.snoozeDurationMinutes(1), 5);
    expect(s.snoozeDurationMinutes(2), 3);
    expect(s.snoozeDurationMinutes(3), 2);
    expect(s.snoozeDurationMinutes(4), 1);
    expect(s.snoozeDurationMinutes(9), 1); // clamps to the last value
  });

  test('snoozeDurationMinutes uses a flat value when set', () {
    const s = RiseSettings(snoozeFlatMinutes: 10);
    expect(s.snoozeDurationMinutes(0), 10);
    expect(s.snoozeDurationMinutes(3), 10);
  });

  test('copyWith and equality', () {
    const s = RiseSettings();
    expect(s.copyWith(snoozeMaxCount: 5).snoozeMaxCount, 5);
    expect(s.copyWith(wakeIntention: 'Stand up').wakeIntention, 'Stand up');
    expect(s.copyWith(), s);
    expect(const RiseSettings(wakeCheckEnabled: false) == const RiseSettings(),
        isFalse);
    expect(
        const RiseSettings(wakeIntention: 'Walk') == const RiseSettings(),
        isFalse);
    expect(const RiseSettings(wakeIntention: 'Walk').hashCode ==
        const RiseSettings().hashCode, isFalse);
  });

  test('target wake time: set, hasTargetWake, equality, and clear', () {
    const unset = RiseSettings();
    final set = unset.copyWith(targetWakeHour: 6, targetWakeMinute: 45);
    expect(set.targetWakeHour, 6);
    expect(set.targetWakeMinute, 45);
    expect(set.hasTargetWake, isTrue);

    // A differing target is not equal to the unset default.
    expect(set == unset, isFalse);
    expect(set.hashCode == unset.hashCode, isFalse);

    // The clear sentinel resets both components back to null.
    final cleared = set.copyWith(clearTargetWake: true);
    expect(cleared.targetWakeHour, isNull);
    expect(cleared.targetWakeMinute, isNull);
    expect(cleared.hasTargetWake, isFalse);
    expect(cleared, unset);

    // clearTargetWake wins even if new values are also passed.
    expect(
        set.copyWith(targetWakeHour: 9, clearTargetWake: true).hasTargetWake,
        isFalse);
  });
}
