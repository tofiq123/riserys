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
}
