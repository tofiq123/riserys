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
    expect(s.smartWakeCheck, isFalse);
    expect(s.sunriseWake, isFalse);
    expect(s.realLightPrompt, isFalse);
    expect(s.use24HourTime, isFalse);
  });

  test('use24HourTime defaults off; copyWith and equality', () {
    const s = RiseSettings();
    expect(s.copyWith(use24HourTime: true).use24HourTime, isTrue);
    expect(const RiseSettings(use24HourTime: true) == const RiseSettings(),
        isFalse);
    expect(
        const RiseSettings(use24HourTime: true).hashCode ==
            const RiseSettings().hashCode,
        isFalse);
    // Unrelated copyWith preserves it.
    expect(
        const RiseSettings(use24HourTime: true)
            .copyWith(snoozeMaxCount: 2)
            .use24HourTime,
        isTrue);
  });

  test('realLightPrompt defaults off; copyWith and equality', () {
    const s = RiseSettings();
    expect(s.copyWith(realLightPrompt: true).realLightPrompt, isTrue);
    expect(const RiseSettings(realLightPrompt: true) == const RiseSettings(),
        isFalse);
    expect(
        const RiseSettings(realLightPrompt: true).hashCode ==
            const RiseSettings().hashCode,
        isFalse);
    // Unrelated copyWith preserves it.
    expect(
        const RiseSettings(realLightPrompt: true)
            .copyWith(snoozeMaxCount: 2)
            .realLightPrompt,
        isTrue);
  });

  test('sunriseWake copyWith and equality', () {
    const s = RiseSettings();
    expect(s.copyWith(sunriseWake: true).sunriseWake, isTrue);
    expect(const RiseSettings(sunriseWake: true) == const RiseSettings(),
        isFalse);
    expect(
        const RiseSettings(sunriseWake: true).hashCode ==
            const RiseSettings().hashCode,
        isFalse);
    // Unrelated copyWith preserves it.
    expect(
        const RiseSettings(sunriseWake: true)
            .copyWith(snoozeMaxCount: 2)
            .sunriseWake,
        isTrue);
  });

  test('smartWakeCheck copyWith and equality', () {
    const s = RiseSettings();
    expect(s.copyWith(smartWakeCheck: true).smartWakeCheck, isTrue);
    expect(const RiseSettings(smartWakeCheck: true) == const RiseSettings(),
        isFalse);
    expect(
        const RiseSettings(smartWakeCheck: true).hashCode ==
            const RiseSettings().hashCode,
        isFalse);
    // Unrelated copyWith preserves it.
    expect(
        const RiseSettings(smartWakeCheck: true)
            .copyWith(snoozeMaxCount: 2)
            .smartWakeCheck,
        isTrue);
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
