import 'package:shared_preferences/shared_preferences.dart';

/// Small key-value store for app-level preferences. Deliberately separate from
/// the alarm Drift database (the alarm source of truth) — these are app prefs,
/// not alarm data. Backed by SharedPreferences.
class AppSettings {
  AppSettings(this._prefs);

  final SharedPreferences _prefs;

  static Future<AppSettings> load() async =>
      AppSettings(await SharedPreferences.getInstance());

  static const _kOnboardingComplete = 'onboardingComplete';

  /// Whether the user has finished (or skipped) onboarding. The launcher reads
  /// this to decide between Onboarding and the app shell.
  bool get onboardingComplete => _prefs.getBool(_kOnboardingComplete) ?? false;

  Future<void> setOnboardingComplete(bool value) =>
      _prefs.setBool(_kOnboardingComplete, value);
}
