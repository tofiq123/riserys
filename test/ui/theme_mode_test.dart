import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/app_settings.dart';
import 'package:rise/domain/rise_settings.dart';
import 'package:rise/ui/screens/settings_screen.dart';
import 'package:rise/ui/state/settings_providers.dart';
import 'package:rise/ui/theme/tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Spec dark-palette ground/ink values (see tokens.dart).
const _lightBg = Color(0xFFF4F4F5);
const _darkBg = Color(0xFF09090B);

/// A minimal stand-in for the app root: watches the theme setting, resolves it
/// to a brightness, and sets the [RiseColors] palette BEFORE building its
/// child — exactly as `_RiseAppState.build` does. `system` resolves to light
/// here (the test platform's default brightness).
class _ThemedHost extends ConsumerWidget {
  const _ThemedHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(settingsProvider.select((s) => s.themeMode));
    final brightness = switch (mode) {
      RiseThemeMode.dark => Brightness.dark,
      _ => Brightness.light,
    };
    RiseColors.setPalette(brightness);
    return const MaterialApp(home: SettingsScreen());
  }
}

Future<void> _pump(WidgetTester t, Widget w) async {
  t.view.physicalSize = const Size(1200, 4000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(w);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Never leak a swapped palette into other tests in this isolate.
  tearDown(() => RiseColors.setPalette(Brightness.light));

  test('setPalette swaps RiseColors between the light and dark palettes', () {
    RiseColors.setPalette(Brightness.dark);
    expect(RiseColors.appBg, _darkBg);
    expect(RiseColors.text, const Color(0xFFFAFAFA));
    expect(RiseColors.primary, const Color(0xFFFAFAFA)); // inverted on dark
    expect(RiseColors.brightness, Brightness.dark);

    RiseColors.setPalette(Brightness.light);
    expect(RiseColors.appBg, _lightBg);
    expect(RiseColors.text, const Color(0xFF09090B));
    expect(RiseColors.primary, const Color(0xFF18181B));
    expect(RiseColors.brightness, Brightness.light);
  });

  test('AppSettings persists themeMode (default system)', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppSettings.load();
    expect(store.themeMode, RiseThemeMode.system);
    await store.setThemeMode(RiseThemeMode.dark);
    expect(store.themeMode, RiseThemeMode.dark);
    // Survives a fresh load of the same backing store.
    final reloaded = await AppSettings.load();
    expect(reloaded.themeMode, RiseThemeMode.dark);
  });

  testWidgets('choosing Dark swaps the screen ground to the dark palette',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppSettings.load();
    await _pump(
        t,
        ProviderScope(
          overrides: [appSettingsProvider.overrideWithValue(store)],
          child: const _ThemedHost(),
        ));
    await t.pump();

    Color? groundColor() =>
        t.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor;

    // Default (system → light in the test harness).
    expect(groundColor(), _lightBg);

    // Pick Dark: the setting change rebuilds the host, which re-runs setPalette,
    // so the Settings scaffold re-reads a dark ground colour.
    await t.tap(find.text('Dark'));
    await t.pumpAndSettle();
    expect(groundColor(), _darkBg);
    expect(store.themeMode, RiseThemeMode.dark); // and it persisted

    // Back to Light restores the original ground.
    await t.tap(find.text('Light'));
    await t.pumpAndSettle();
    expect(groundColor(), _lightBg);
  });
}
