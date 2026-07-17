import 'package:shared_preferences/shared_preferences.dart';

import '../domain/rise_settings.dart';

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

  static const _kSnoozeMaxCount = 'snoozeMaxCount';
  static const _kSnoozeFlatMinutes = 'snoozeFlatMinutes';
  static const _kWakeCheckEnabled = 'wakeCheckEnabled';
  static const _kWakeCheckDelayMinutes = 'wakeCheckDelayMinutes';

  int get snoozeMaxCount => _prefs.getInt(_kSnoozeMaxCount) ?? 3;
  Future<void> setSnoozeMaxCount(int v) => _prefs.setInt(_kSnoozeMaxCount, v);

  int get snoozeFlatMinutes => _prefs.getInt(_kSnoozeFlatMinutes) ?? 0;
  Future<void> setSnoozeFlatMinutes(int v) =>
      _prefs.setInt(_kSnoozeFlatMinutes, v);

  bool get wakeCheckEnabled => _prefs.getBool(_kWakeCheckEnabled) ?? true;
  Future<void> setWakeCheckEnabled(bool v) =>
      _prefs.setBool(_kWakeCheckEnabled, v);

  int get wakeCheckDelayMinutes => _prefs.getInt(_kWakeCheckDelayMinutes) ?? 5;
  Future<void> setWakeCheckDelayMinutes(int v) =>
      _prefs.setInt(_kWakeCheckDelayMinutes, v);

  /// A snapshot of the mutable settings (snooze + wake-check).
  RiseSettings get settings => RiseSettings(
        snoozeMaxCount: snoozeMaxCount,
        snoozeFlatMinutes: snoozeFlatMinutes,
        wakeCheckEnabled: wakeCheckEnabled,
        wakeCheckDelayMinutes: wakeCheckDelayMinutes,
      );
}
