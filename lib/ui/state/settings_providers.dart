import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_settings.dart';
import '../../domain/rise_settings.dart';

/// The app's settings store. main() overrides this with the instance loaded at
/// startup; tests override it with an AppSettings over mock preferences.
final appSettingsProvider = Provider<AppSettings>((ref) {
  throw UnimplementedError('appSettingsProvider must be overridden in main()');
});

/// Editable snooze + wake-check settings, backed by [AppSettings].
class SettingsController extends StateNotifier<RiseSettings> {
  SettingsController(this._store) : super(_store.settings);

  final AppSettings _store;

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
}

final settingsProvider =
    StateNotifierProvider<SettingsController, RiseSettings>(
        (ref) => SettingsController(ref.watch(appSettingsProvider)));

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
