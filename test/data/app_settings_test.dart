import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/app_settings.dart';
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
}
