import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/app_settings.dart';
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
    await t.tap(find.byKey(const Key('wake-check-switch')));
    await t.pump();
    expect(store.wakeCheckEnabled, isFalse); // default true → toggled off
  });

  testWidgets('toggling adaptive difficulty persists it', (t) async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppSettings.load();
    await _pump(
        t,
        ProviderScope(
          overrides: [appSettingsProvider.overrideWithValue(store)],
          child: const MaterialApp(home: SettingsScreen()),
        ));
    await t.pump();
    expect(store.adaptiveMissions, isFalse); // default off
    await t.tap(find.byKey(const Key('adaptive-missions-switch')));
    await t.pump();
    expect(store.adaptiveMissions, isTrue);
  });

  testWidgets('toggling the smart wake-check persists it (default off)',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppSettings.load();
    await _pump(
        t,
        ProviderScope(
          overrides: [appSettingsProvider.overrideWithValue(store)],
          child: const MaterialApp(home: SettingsScreen()),
        ));
    await t.pump();
    expect(store.smartWakeCheck, isFalse); // default off
    await t.tap(find.byKey(const Key('smart-wake-check-switch')));
    await t.pump();
    expect(store.smartWakeCheck, isTrue);
  });

  testWidgets('toggling the sunrise wake persists it (default off)', (t) async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppSettings.load();
    await _pump(
        t,
        ProviderScope(
          overrides: [appSettingsProvider.overrideWithValue(store)],
          child: const MaterialApp(home: SettingsScreen()),
        ));
    await t.pump();
    expect(store.sunriseWake, isFalse); // default off
    await t.tap(find.byKey(const Key('sunrise-wake-switch')));
    await t.pump();
    expect(store.sunriseWake, isTrue);
  });

  testWidgets('toggling the real-light prompt persists it (default on)',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppSettings.load();
    await _pump(
        t,
        ProviderScope(
          overrides: [appSettingsProvider.overrideWithValue(store)],
          child: const MaterialApp(home: SettingsScreen()),
        ));
    await t.pump();
    expect(store.realLightPrompt, isTrue); // default on
    await t.tap(find.byKey(const Key('real-light-prompt-switch')));
    await t.pump();
    expect(store.realLightPrompt, isFalse);
  });

  testWidgets('editing the wake plan persists it', (t) async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppSettings.load();
    await _pump(
        t,
        ProviderScope(
          overrides: [appSettingsProvider.overrideWithValue(store)],
          child: const MaterialApp(home: SettingsScreen()),
        ));
    await t.pump();
    await t.enterText(
        find.byKey(const Key('wake-plan-field')), 'Walk to the kitchen');
    await t.pump();
    expect(store.wakeIntention, 'Walk to the kitchen');
  });

  testWidgets('the wake plan field seeds from the persisted value', (t) async {
    SharedPreferences.setMockInitialValues({'wakeIntention': 'Stand up'});
    final store = await AppSettings.load();
    await _pump(
        t,
        ProviderScope(
          overrides: [appSettingsProvider.overrideWithValue(store)],
          child: const MaterialApp(home: SettingsScreen()),
        ));
    await t.pump();
    expect(find.text('Stand up'), findsOneWidget);
  });

  testWidgets('sleep goal shows Not set and saving persists the default',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppSettings.load();
    await _pump(
        t,
        ProviderScope(
          overrides: [appSettingsProvider.overrideWithValue(store)],
          child: const MaterialApp(home: SettingsScreen()),
        ));
    await t.pump();
    expect(find.text('Not set'), findsOneWidget);

    await t.tap(find.byKey(const Key('sleep-goal-card')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('sleep-goal-save')));
    await t.pumpAndSettle();

    expect(store.targetWakeHour, 7); // seeded default 7:00 AM
    expect(store.targetWakeMinute, 0);
    expect(find.text('7:00 AM'), findsOneWidget);
  });

  testWidgets('sleep goal shows the persisted time', (t) async {
    SharedPreferences.setMockInitialValues(
        {'targetWakeHour': 6, 'targetWakeMinute': 45});
    final store = await AppSettings.load();
    await _pump(
        t,
        ProviderScope(
          overrides: [appSettingsProvider.overrideWithValue(store)],
          child: const MaterialApp(home: SettingsScreen()),
        ));
    await t.pump();
    expect(find.text('6:45 AM'), findsOneWidget);
  });
}
