import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/app_settings.dart';
import 'package:rise/domain/rise_settings.dart';
import 'package:rise/ui/state/settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records the native bedtime-reminder calls the controller makes, optionally
/// failing them to prove a platform hiccup never breaks the settings write.
class _FakeBedtimeHost implements BedtimeReminderHost {
  final calls = <String>[];
  bool throwOnCall = false;

  @override
  Future<void> schedule(int hour, int minute) async {
    if (throwOnCall) throw StateError('channel down');
    calls.add('schedule $hour:$minute');
  }

  @override
  Future<void> cancel() async {
    if (throwOnCall) throw StateError('channel down');
    calls.add('cancel');
  }
}

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

  test('SettingsController sets and clears the home anchor', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppSettings.load();
    final c = ProviderContainer(
        overrides: [appSettingsProvider.overrideWithValue(store)]);
    addTearDown(c.dispose);

    expect(c.read(settingsProvider).hasHome, isFalse);
    await c.read(settingsProvider.notifier).setHome(52.52, 13.405);
    expect(c.read(settingsProvider).homeLat, 52.52);
    expect(c.read(settingsProvider).homeLng, 13.405);
    expect((await AppSettings.load()).homeLat, 52.52); // persisted

    await c.read(settingsProvider.notifier).clearHome();
    expect(c.read(settingsProvider).hasHome, isFalse);
    expect((await AppSettings.load()).homeLat, isNull);
  });

  test('SettingsController sets the home share tier (default off)', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppSettings.load();
    final c = ProviderContainer(
        overrides: [appSettingsProvider.overrideWithValue(store)]);
    addTearDown(c.dispose);

    expect(c.read(settingsProvider).homeShare, HomeShareTier.off);
    await c.read(settingsProvider.notifier).setHomeShare(HomeShareTier.crew);
    expect(c.read(settingsProvider).homeShare, HomeShareTier.crew);
    expect((await AppSettings.load()).homeShare, HomeShareTier.crew);
  });

  test('enabling the bedtime reminder persists it and arms the native side',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppSettings.load();
    final host = _FakeBedtimeHost();
    final c = ProviderContainer(overrides: [
      appSettingsProvider.overrideWithValue(store),
      bedtimeReminderHostProvider.overrideWithValue(host),
    ]);
    addTearDown(c.dispose);

    expect(c.read(settingsProvider).bedtimeReminderEnabled, isFalse);
    await c.read(settingsProvider.notifier).setBedtimeReminderEnabled(true);
    expect(c.read(settingsProvider).bedtimeReminderEnabled, isTrue);
    expect((await AppSettings.load()).bedtimeReminderEnabled, isTrue);
    expect(host.calls, ['schedule 22:30'],
        reason: 'armed at the default 22:30 on enable');
  });

  test('changing the bedtime while enabled re-arms at the new time', () async {
    SharedPreferences.setMockInitialValues({'bedtimeReminderEnabled': true});
    final store = await AppSettings.load();
    final host = _FakeBedtimeHost();
    final c = ProviderContainer(overrides: [
      appSettingsProvider.overrideWithValue(store),
      bedtimeReminderHostProvider.overrideWithValue(host),
    ]);
    addTearDown(c.dispose);

    await c.read(settingsProvider.notifier).setBedtimeTime(23, 15);
    expect(c.read(settingsProvider).bedtimeHour, 23);
    expect(c.read(settingsProvider).bedtimeMinute, 15);
    expect((await AppSettings.load()).bedtimeHour, 23);
    expect(host.calls, ['schedule 23:15']);
  });

  test('disabling the bedtime reminder cancels the native side', () async {
    SharedPreferences.setMockInitialValues({'bedtimeReminderEnabled': true});
    final store = await AppSettings.load();
    final host = _FakeBedtimeHost();
    final c = ProviderContainer(overrides: [
      appSettingsProvider.overrideWithValue(store),
      bedtimeReminderHostProvider.overrideWithValue(host),
    ]);
    addTearDown(c.dispose);

    await c.read(settingsProvider.notifier).setBedtimeReminderEnabled(false);
    expect(c.read(settingsProvider).bedtimeReminderEnabled, isFalse);
    expect((await AppSettings.load()).bedtimeReminderEnabled, isFalse);
    expect(host.calls, ['cancel']);
  });

  test('a failing bedtime host never breaks the settings write', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppSettings.load();
    final host = _FakeBedtimeHost()..throwOnCall = true;
    final c = ProviderContainer(overrides: [
      appSettingsProvider.overrideWithValue(store),
      bedtimeReminderHostProvider.overrideWithValue(host),
    ]);
    addTearDown(c.dispose);

    // Must not throw, and the setting must still persist + update state.
    await c.read(settingsProvider.notifier).setBedtimeReminderEnabled(true);
    expect(c.read(settingsProvider).bedtimeReminderEnabled, isTrue);
    expect((await AppSettings.load()).bedtimeReminderEnabled, isTrue);
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
