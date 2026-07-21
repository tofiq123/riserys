import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/app_settings.dart';
import 'package:rise/domain/rise_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('onboardingComplete defaults to false, round-trips, and persists', () async {
    SharedPreferences.setMockInitialValues({});
    final s = await AppSettings.load();
    expect(s.onboardingComplete, isFalse);

    await s.setOnboardingComplete(true);
    expect(s.onboardingComplete, isTrue);

    // A freshly loaded instance sees the persisted value.
    final s2 = await AppSettings.load();
    expect(s2.onboardingComplete, isTrue);
  });

  test('snooze + wake-check settings default and round-trip', () async {
    SharedPreferences.setMockInitialValues({});
    final s = await AppSettings.load();
    expect(s.snoozeMaxCount, 3);
    expect(s.snoozeFlatMinutes, 0);
    expect(s.wakeCheckEnabled, isTrue);
    expect(s.wakeCheckDelayMinutes, 5);

    await s.setSnoozeMaxCount(2);
    await s.setSnoozeFlatMinutes(10);
    await s.setWakeCheckEnabled(false);
    await s.setWakeCheckDelayMinutes(15);

    final s2 = await AppSettings.load();
    expect(s2.snoozeMaxCount, 2);
    expect(s2.snoozeFlatMinutes, 10);
    expect(s2.wakeCheckEnabled, isFalse);
    expect(s2.wakeCheckDelayMinutes, 15);
    expect(s2.settings.snoozeMaxCount, 2); // snapshot
  });

  test('wakeIntention defaults empty, round-trips, and reaches the snapshot',
      () async {
    SharedPreferences.setMockInitialValues({});
    final s = await AppSettings.load();
    expect(s.wakeIntention, '');
    expect(s.settings.wakeIntention, '');

    await s.setWakeIntention('Put my feet on the floor');

    final s2 = await AppSettings.load();
    expect(s2.wakeIntention, 'Put my feet on the floor');
    expect(s2.settings.wakeIntention, 'Put my feet on the floor');
  });

  test('targetWakeTime defaults unset, round-trips, and clears', () async {
    SharedPreferences.setMockInitialValues({});
    final s = await AppSettings.load();
    expect(s.targetWakeHour, isNull);
    expect(s.targetWakeMinute, isNull);
    expect(s.settings.hasTargetWake, isFalse);

    await s.setTargetWakeTime(6, 30);

    final s2 = await AppSettings.load();
    expect(s2.targetWakeHour, 6);
    expect(s2.targetWakeMinute, 30);
    expect(s2.settings.targetWakeHour, 6);
    expect(s2.settings.targetWakeMinute, 30);

    await s2.clearTargetWakeTime();
    final s3 = await AppSettings.load();
    expect(s3.targetWakeHour, isNull);
    expect(s3.targetWakeMinute, isNull);
  });

  test('adaptiveMissions defaults false, round-trips, and reaches the snapshot',
      () async {
    SharedPreferences.setMockInitialValues({});
    final s = await AppSettings.load();
    expect(s.adaptiveMissions, isFalse);
    expect(s.settings.adaptiveMissions, isFalse);

    await s.setAdaptiveMissions(true);

    final s2 = await AppSettings.load();
    expect(s2.adaptiveMissions, isTrue);
    expect(s2.settings.adaptiveMissions, isTrue);
  });

  test('smartWakeCheck defaults false, round-trips, and reaches the snapshot',
      () async {
    SharedPreferences.setMockInitialValues({});
    final s = await AppSettings.load();
    expect(s.smartWakeCheck, isFalse);
    expect(s.settings.smartWakeCheck, isFalse);

    await s.setSmartWakeCheck(true);

    final s2 = await AppSettings.load();
    expect(s2.smartWakeCheck, isTrue);
    expect(s2.settings.smartWakeCheck, isTrue);
  });

  test('sunriseWake defaults false, round-trips, and reaches the snapshot',
      () async {
    SharedPreferences.setMockInitialValues({});
    final s = await AppSettings.load();
    expect(s.sunriseWake, isFalse);
    expect(s.settings.sunriseWake, isFalse);

    await s.setSunriseWake(true);

    final s2 = await AppSettings.load();
    expect(s2.sunriseWake, isTrue);
    expect(s2.settings.sunriseWake, isTrue);
  });

  test('realLightPrompt defaults false, round-trips, and reaches the snapshot',
      () async {
    SharedPreferences.setMockInitialValues({});
    final s = await AppSettings.load();
    expect(s.realLightPrompt, isFalse);
    expect(s.settings.realLightPrompt, isFalse);

    await s.setRealLightPrompt(false);

    final s2 = await AppSettings.load();
    expect(s2.realLightPrompt, isFalse);
    expect(s2.settings.realLightPrompt, isFalse);
  });

  test('home anchor defaults unset, round-trips, clears, reaches the snapshot',
      () async {
    SharedPreferences.setMockInitialValues({});
    final s = await AppSettings.load();
    expect(s.homeLat, isNull);
    expect(s.homeLng, isNull);
    expect(s.settings.hasHome, isFalse);

    await s.setHome(52.52, 13.405);

    final s2 = await AppSettings.load();
    expect(s2.homeLat, 52.52);
    expect(s2.homeLng, 13.405);
    expect(s2.settings.hasHome, isTrue);

    await s2.clearHome();
    final s3 = await AppSettings.load();
    expect(s3.homeLat, isNull);
    expect(s3.homeLng, isNull);
    expect(s3.settings.hasHome, isFalse);
  });

  test('homeShare defaults off, round-trips, unknown value falls back to off',
      () async {
    SharedPreferences.setMockInitialValues({});
    final s = await AppSettings.load();
    expect(s.homeShare, HomeShareTier.off); // privacy: default off
    expect(s.settings.homeShare, HomeShareTier.off);

    await s.setHomeShare(HomeShareTier.crew);

    final s2 = await AppSettings.load();
    expect(s2.homeShare, HomeShareTier.crew);
    expect(s2.settings.homeShare, HomeShareTier.crew);

    // A corrupt/legacy value falls back to off, the safe direction.
    SharedPreferences.setMockInitialValues({'homeShare': 'everyone'});
    final s3 = await AppSettings.load();
    expect(s3.homeShare, HomeShareTier.off);
  });

  test('use24HourTime defaults false, round-trips, and reaches the snapshot',
      () async {
    SharedPreferences.setMockInitialValues({});
    final s = await AppSettings.load();
    expect(s.use24HourTime, isFalse);
    expect(s.settings.use24HourTime, isFalse);

    await s.setUse24HourTime(true);

    final s2 = await AppSettings.load();
    expect(s2.use24HourTime, isTrue);
    expect(s2.settings.use24HourTime, isTrue);
  });
}
