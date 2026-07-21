import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/app_settings.dart';
import 'package:rise/domain/rise_settings.dart';
import 'package:rise/ui/state/settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SettingsController persists a change and updates state', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppSettings.load();
    final c = ProviderContainer(
        overrides: [appSettingsProvider.overrideWithValue(store)]);
    addTearDown(c.dispose);

    expect(c.read(settingsProvider).snoozeMaxCount, 3);
    await c.read(settingsProvider.notifier).setSnoozeMaxCount(1);
    expect(c.read(settingsProvider).snoozeMaxCount, 1); // state updated
    expect((await AppSettings.load()).snoozeMaxCount, 1); // persisted
  });

  test('SettingsController toggles the wake-check', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppSettings.load();
    final c = ProviderContainer(
        overrides: [appSettingsProvider.overrideWithValue(store)]);
    addTearDown(c.dispose);
    await c.read(settingsProvider.notifier).setWakeCheckEnabled(false);
    expect(c.read(settingsProvider).wakeCheckEnabled, isFalse);
  });

  test('SettingsController toggles the smart wake-check (default off)', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppSettings.load();
    final c = ProviderContainer(
        overrides: [appSettingsProvider.overrideWithValue(store)]);
    addTearDown(c.dispose);
    expect(c.read(settingsProvider).smartWakeCheck, isFalse);
    await c.read(settingsProvider.notifier).setSmartWakeCheck(true);
    expect(c.read(settingsProvider).smartWakeCheck, isTrue); // state updated
    expect((await AppSettings.load()).smartWakeCheck, isTrue); // persisted
  });

  test('SettingsController toggles the sunrise wake (default off)', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppSettings.load();
    final c = ProviderContainer(
        overrides: [appSettingsProvider.overrideWithValue(store)]);
    addTearDown(c.dispose);
    expect(c.read(settingsProvider).sunriseWake, isFalse);
    await c.read(settingsProvider.notifier).setSunriseWake(true);
    expect(c.read(settingsProvider).sunriseWake, isTrue); // state updated
    expect((await AppSettings.load()).sunriseWake, isTrue); // persisted
  });

  test('SettingsController toggles the real-light prompt (default off)',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppSettings.load();
    final c = ProviderContainer(
        overrides: [appSettingsProvider.overrideWithValue(store)]);
    addTearDown(c.dispose);
    expect(c.read(settingsProvider).realLightPrompt, isFalse);
    await c.read(settingsProvider.notifier).setRealLightPrompt(false);
    expect(c.read(settingsProvider).realLightPrompt, isFalse); // state updated
    expect((await AppSettings.load()).realLightPrompt, isFalse); // persisted
  });

  test('SettingsController toggles 24-hour time (default off)', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppSettings.load();
    final c = ProviderContainer(
        overrides: [appSettingsProvider.overrideWithValue(store)]);
    addTearDown(c.dispose);
    expect(c.read(settingsProvider).use24HourTime, isFalse);
    await c.read(settingsProvider.notifier).setUse24HourTime(true);
    expect(c.read(settingsProvider).use24HourTime, isTrue); // state updated
    expect((await AppSettings.load()).use24HourTime, isTrue); // persisted
  });

  test('SettingsController sets and clears the steady wake time', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppSettings.load();
    final c = ProviderContainer(
        overrides: [appSettingsProvider.overrideWithValue(store)]);
    addTearDown(c.dispose);

    expect(c.read(settingsProvider).hasTargetWake, isFalse);
    await c.read(settingsProvider.notifier).setTargetWakeTime(6, 15);
    expect(c.read(settingsProvider).targetWakeHour, 6);
    expect(c.read(settingsProvider).targetWakeMinute, 15);
    expect((await AppSettings.load()).targetWakeHour, 6); // persisted

    await c.read(settingsProvider.notifier).clearTargetWakeTime();
    expect(c.read(settingsProvider).hasTargetWake, isFalse);
    expect((await AppSettings.load()).targetWakeHour, isNull);
  });

  test(
      'currentSettingsProvider falls back to defaults when the store is unavailable',
      () {
    // appSettingsProvider is NOT overridden here, so settingsProvider's build
    // throws — currentSettingsProvider must still yield defaults, not rethrow.
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(currentSettingsProvider), const RiseSettings());
  });
}
