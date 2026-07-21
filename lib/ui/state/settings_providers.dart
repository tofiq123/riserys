import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_settings.dart';
import '../../data/native/alarm_api.g.dart';
import '../../domain/rise_settings.dart';

/// The app's settings store. main() overrides this with the instance loaded at
/// startup; tests override it with an AppSettings over mock preferences.
final appSettingsProvider = Provider<AppSettings>((ref) {
  throw UnimplementedError('appSettingsProvider must be overridden in main()');
});

/// Thin seam over the native bedtime-reminder host calls, so the settings
/// controller can (re)arm or cancel the nightly wind-down notification without
/// tests needing a real platform channel. The warm copy lives here — natively
/// it is just a title and body.
class BedtimeReminderHost {
  const BedtimeReminderHost();

  static const _title = 'Wind down for tomorrow';
  static const _body =
      'A gentle nudge: heading to bed soon makes the morning easier.';

  Future<void> schedule(int hour, int minute) =>
      AlarmHostApi().scheduleBedtimeReminder(hour, minute, _title, _body);

  Future<void> cancel() => AlarmHostApi().cancelBedtimeReminder();
}

/// The bedtime host used by [settingsProvider]; tests override this with a
/// fake to observe scheduling without a platform channel.
final bedtimeReminderHostProvider =
    Provider<BedtimeReminderHost>((ref) => const BedtimeReminderHost());

/// Editable snooze + wake-check settings, backed by [AppSettings].
class SettingsController extends StateNotifier<RiseSettings> {
  SettingsController(this._store,
      {BedtimeReminderHost bedtime = const BedtimeReminderHost()})
      : _bedtime = bedtime,
        super(_store.settings);

  final AppSettings _store;
  final BedtimeReminderHost _bedtime;

  Future<void> setSnoozeMaxCount(int v) async {
    await _store.setSnoozeMaxCount(v);
    state = state.copyWith(snoozeMaxCount: v);
  }

  Future<void> setSnoozeFlatMinutes(int v) async {
    await _store.setSnoozeFlatMinutes(v);
    state = state.copyWith(snoozeFlatMinutes: v);
  }

  Future<void> setWakeCheckEnabled(bool v) async {
    await _store.setWakeCheckEnabled(v);
    state = state.copyWith(wakeCheckEnabled: v);
  }

  Future<void> setWakeCheckDelayMinutes(int v) async {
    await _store.setWakeCheckDelayMinutes(v);
    state = state.copyWith(wakeCheckDelayMinutes: v);
  }

  Future<void> setWakeIntention(String v) async {
    final trimmed = v.trim();
    await _store.setWakeIntention(trimmed);
    state = state.copyWith(wakeIntention: trimmed);
  }

  Future<void> setTargetWakeTime(int hour, int minute) async {
    await _store.setTargetWakeTime(hour, minute);
    state = state.copyWith(targetWakeHour: hour, targetWakeMinute: minute);
  }

  Future<void> clearTargetWakeTime() async {
    await _store.clearTargetWakeTime();
    state = state.copyWith(clearTargetWake: true);
  }

  Future<void> setAdaptiveMissions(bool v) async {
    await _store.setAdaptiveMissions(v);
    state = state.copyWith(adaptiveMissions: v);
  }

  Future<void> setSmartWakeCheck(bool v) async {
    await _store.setSmartWakeCheck(v);
    state = state.copyWith(smartWakeCheck: v);
  }

  Future<void> setSunriseWake(bool v) async {
    await _store.setSunriseWake(v);
    state = state.copyWith(sunriseWake: v);
  }

  Future<void> setRealLightPrompt(bool v) async {
    await _store.setRealLightPrompt(v);
    state = state.copyWith(realLightPrompt: v);
  }

  Future<void> setUse24HourTime(bool v) async {
    await _store.setUse24HourTime(v);
    state = state.copyWith(use24HourTime: v);
  }

  Future<void> setThemeMode(RiseThemeMode v) async {
    await _store.setThemeMode(v);
    state = state.copyWith(themeMode: v);
  }

  Future<void> setBedtimeReminderEnabled(bool v) async {
    await _store.setBedtimeReminderEnabled(v);
    state = state.copyWith(bedtimeReminderEnabled: v);
    await _syncBedtimeReminder();
  }

  Future<void> setBedtimeTime(int hour, int minute) async {
    await _store.setBedtimeTime(hour, minute);
    state = state.copyWith(bedtimeHour: hour, bedtimeMinute: minute);
    await _syncBedtimeReminder();
  }

  /// Pushes the current bedtime settings to the native scheduler: armed at the
  /// chosen time while enabled, cancelled when off. Best-effort — a platform
  /// hiccup must never fail the settings write itself (the persisted state is
  /// re-pushed on the next change, and natively re-armed on boot).
  Future<void> _syncBedtimeReminder() async {
    try {
      if (state.bedtimeReminderEnabled) {
        await _bedtime.schedule(state.bedtimeHour, state.bedtimeMinute);
      } else {
        await _bedtime.cancel();
      }
    } catch (e) {
      debugPrint('Rise: bedtime-reminder sync failed: $e');
    }
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsController, RiseSettings>(
        (ref) => SettingsController(ref.watch(appSettingsProvider),
            bedtime: ref.watch(bedtimeReminderHostProvider)));

/// Read-only view of the current settings, for consumers that only read (e.g.
/// the ring screen). Trivially overridable with a fixed value in tests.
final currentSettingsProvider = Provider<RiseSettings>((ref) {
  // Resilient: a read-only consumer (e.g. the ring screen, which must always
  // render a dismiss gate) gets sensible defaults rather than a thrown
  // UnimplementedError if the settings store failed to load at startup.
  try {
    return ref.watch(settingsProvider);
  } catch (_) {
    return const RiseSettings();
  }
});
