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
  static const _kWakeIntention = 'wakeIntention';
  static const _kTargetWakeHour = 'targetWakeHour';
  static const _kTargetWakeMinute = 'targetWakeMinute';
  static const _kAdaptiveMissions = 'adaptiveMissions';
  static const _kSmartWakeCheck = 'smartWakeCheck';
  static const _kSunriseWake = 'sunriseWake';
  static const _kRealLightPrompt = 'realLightPrompt';
  static const _kUse24HourTime = 'use24HourTime';
  static const _kThemeMode = 'themeMode';
  static const _kHomeLat = 'homeLat';
  static const _kHomeLng = 'homeLng';
  static const _kHomeShare = 'homeShare';
  static const _kBedtimeReminderEnabled = 'bedtimeReminderEnabled';
  static const _kBedtimeHour = 'bedtimeHour';
  static const _kBedtimeMinute = 'bedtimeMinute';

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

  String get wakeIntention => _prefs.getString(_kWakeIntention) ?? '';
  Future<void> setWakeIntention(String v) =>
      _prefs.setString(_kWakeIntention, v);

  /// The steady target wake time (24-hour), or null when unset. The two
  /// components are always stored and cleared together.
  int? get targetWakeHour => _prefs.getInt(_kTargetWakeHour);
  int? get targetWakeMinute => _prefs.getInt(_kTargetWakeMinute);

  Future<void> setTargetWakeTime(int hour, int minute) async {
    await _prefs.setInt(_kTargetWakeHour, hour);
    await _prefs.setInt(_kTargetWakeMinute, minute);
  }

  Future<void> clearTargetWakeTime() async {
    await _prefs.remove(_kTargetWakeHour);
    await _prefs.remove(_kTargetWakeMinute);
  }

  bool get adaptiveMissions => _prefs.getBool(_kAdaptiveMissions) ?? false;
  Future<void> setAdaptiveMissions(bool v) =>
      _prefs.setBool(_kAdaptiveMissions, v);

  /// Opt-in smart wake-check (Phase 11). Default off → the wake-check behaves
  /// exactly as before unless the user enables it.
  bool get smartWakeCheck => _prefs.getBool(_kSmartWakeCheck) ?? false;
  Future<void> setSmartWakeCheck(bool v) =>
      _prefs.setBool(_kSmartWakeCheck, v);

  /// Opt-in on-screen sunrise wake (Phase 10, Sensory). Default off — the ring
  /// screen looks exactly as before unless the user enables it.
  bool get sunriseWake => _prefs.getBool(_kSunriseWake) ?? false;
  Future<void> setSunriseWake(bool v) => _prefs.setBool(_kSunriseWake, v);

  /// The honest "get real light" ring prompt (Phase 10, Sensory). Default
  /// off — opt-in via Settings, so the ring screen looks exactly as before
  /// unless the user enables it.
  bool get realLightPrompt => _prefs.getBool(_kRealLightPrompt) ?? false;
  Future<void> setRealLightPrompt(bool v) =>
      _prefs.setBool(_kRealLightPrompt, v);

  /// Show times in 24-hour form instead of 12-hour AM/PM. Default off (AM/PM),
  /// so existing users see exactly what they saw before unless they opt in.
  bool get use24HourTime => _prefs.getBool(_kUse24HourTime) ?? false;
  Future<void> setUse24HourTime(bool v) =>
      _prefs.setBool(_kUse24HourTime, v);

  /// The colour theme mode, persisted by enum name. Default [RiseThemeMode.
  /// system] follows the OS. Unknown/legacy values fall back to system.
  RiseThemeMode get themeMode {
    final name = _prefs.getString(_kThemeMode);
    return RiseThemeMode.values
        .firstWhere((m) => m.name == name, orElse: () => RiseThemeMode.system);
  }

  Future<void> setThemeMode(RiseThemeMode v) =>
      _prefs.setString(_kThemeMode, v.name);

  /// The home anchor, or null when unset. DEVICE-LOCAL ONLY: these two keys
  /// live in this on-device store and are deliberately NOT part of the
  /// account-backup payload (`encodeBackup` serializes only alarms + wake
  /// events) and are never sent to Supabase. The components are always stored
  /// and cleared together.
  double? get homeLat => _prefs.getDouble(_kHomeLat);
  double? get homeLng => _prefs.getDouble(_kHomeLng);

  Future<void> setHome(double lat, double lng) async {
    await _prefs.setDouble(_kHomeLat, lat);
    await _prefs.setDouble(_kHomeLng, lng);
  }

  Future<void> clearHome() async {
    await _prefs.remove(_kHomeLat);
    await _prefs.remove(_kHomeLng);
  }

  /// The left-home privacy tier, persisted by enum name. Default (and the
  /// fallback for an unknown/legacy value) is [HomeShareTier.off] — the
  /// feature is fully opt-in.
  HomeShareTier get homeShare {
    final name = _prefs.getString(_kHomeShare);
    return HomeShareTier.values
        .firstWhere((t) => t.name == name, orElse: () => HomeShareTier.off);
  }

  Future<void> setHomeShare(HomeShareTier v) =>
      _prefs.setString(_kHomeShare, v.name);

  /// The opt-in nightly wind-down reminder (Phase 8.5). Default off — nothing
  /// fires unless the user enables it.
  bool get bedtimeReminderEnabled =>
      _prefs.getBool(_kBedtimeReminderEnabled) ?? false;
  Future<void> setBedtimeReminderEnabled(bool v) =>
      _prefs.setBool(_kBedtimeReminderEnabled, v);

  /// The wind-down reminder's wall-clock time (24-hour form), default 22:30.
  /// The two components are always stored together.
  int get bedtimeHour => _prefs.getInt(_kBedtimeHour) ?? 22;
  int get bedtimeMinute => _prefs.getInt(_kBedtimeMinute) ?? 30;

  Future<void> setBedtimeTime(int hour, int minute) async {
    await _prefs.setInt(_kBedtimeHour, hour);
    await _prefs.setInt(_kBedtimeMinute, minute);
  }

  /// A snapshot of the mutable settings (snooze + wake-check + wake plan +
  /// steady wake time).
  RiseSettings get settings => RiseSettings(
        snoozeMaxCount: snoozeMaxCount,
        snoozeFlatMinutes: snoozeFlatMinutes,
        wakeCheckEnabled: wakeCheckEnabled,
        wakeCheckDelayMinutes: wakeCheckDelayMinutes,
        wakeIntention: wakeIntention,
        targetWakeHour: targetWakeHour,
        targetWakeMinute: targetWakeMinute,
        adaptiveMissions: adaptiveMissions,
        smartWakeCheck: smartWakeCheck,
        sunriseWake: sunriseWake,
        realLightPrompt: realLightPrompt,
        bedtimeReminderEnabled: bedtimeReminderEnabled,
        bedtimeHour: bedtimeHour,
        bedtimeMinute: bedtimeMinute,
        use24HourTime: use24HourTime,
        themeMode: themeMode,
        homeLat: homeLat,
        homeLng: homeLng,
        homeShare: homeShare,
      );
}
