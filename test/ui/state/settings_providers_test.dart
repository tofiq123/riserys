import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/app_settings.dart';
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
}
