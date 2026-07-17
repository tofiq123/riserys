import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/app_settings.dart';
import 'package:rise/ui/components/rise_switch.dart';
import 'package:rise/ui/screens/settings_screen.dart';
import 'package:rise/ui/state/settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pump(WidgetTester t, Widget w) async {
  t.view.physicalSize = const Size(1200, 4000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(w);
}

Future<Widget> _host() async {
  SharedPreferences.setMockInitialValues({});
  final store = await AppSettings.load();
  return ProviderScope(
    overrides: [appSettingsProvider.overrideWithValue(store)],
    child: const MaterialApp(home: SettingsScreen()),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders the current settings', (t) async {
    await _pump(t, await _host());
    await t.pump();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('3'), findsOneWidget); // max snoozes default
    expect(find.text('5 min'), findsOneWidget); // wake-check delay default
  });

  testWidgets('stepping the snooze max updates the displayed value', (t) async {
    await _pump(t, await _host());
    await t.pump();
    await t.tap(find.byKey(const ValueKey('snooze-max-plus')));
    await t.pump();
    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('toggling the wake-check persists it', (t) async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppSettings.load();
    await _pump(
        t,
        ProviderScope(
          overrides: [appSettingsProvider.overrideWithValue(store)],
          child: const MaterialApp(home: SettingsScreen()),
        ));
    await t.pump();
    await t.tap(find.byType(RiseSwitch));
    await t.pump();
    expect(store.wakeCheckEnabled, isFalse); // default true → toggled off
  });
}
