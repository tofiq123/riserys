import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/app_settings.dart';
import 'package:rise/data/home_location_gateway.dart';
import 'package:rise/domain/rise_settings.dart';
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

  testWidgets(
      'bedtime reminder: toggling persists it and reveals the time row '
      '(default 22:30)', (t) async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppSettings.load();
    await _pump(
        t,
        ProviderScope(
          overrides: [appSettingsProvider.overrideWithValue(store)],
          child: const MaterialApp(home: SettingsScreen()),
        ));
    await t.pump();
    expect(store.bedtimeReminderEnabled, isFalse); // default off
    expect(find.byKey(const Key('bedtime-time-row')), findsNothing);

    await t.tap(find.byKey(const Key('bedtime-reminder-switch')));
    await t.pump();
    expect(store.bedtimeReminderEnabled, isTrue);
    expect(find.byKey(const Key('bedtime-time-row')), findsOneWidget);
    expect(find.text('10:30 PM'), findsOneWidget); // 22:30 in 12h form
  });

  testWidgets('bedtime time sheet opens and Save persists the time', (t) async {
    SharedPreferences.setMockInitialValues({'bedtimeReminderEnabled': true});
    final store = await AppSettings.load();
    await _pump(
        t,
        ProviderScope(
          overrides: [appSettingsProvider.overrideWithValue(store)],
          child: const MaterialApp(home: SettingsScreen()),
        ));
    await t.pump();
    await t.tap(find.byKey(const Key('bedtime-time-row')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('bedtime-time-save')), findsOneWidget);
    await t.tap(find.byKey(const Key('bedtime-time-save')));
    await t.pumpAndSettle();
    // Saving without touching the dial persists the current (default) time.
    expect(store.bedtimeHour, 22);
    expect(store.bedtimeMinute, 30);
  });

  testWidgets('toggling the real-light prompt persists it (default off)',
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
    expect(store.realLightPrompt, isFalse); // default off
    await t.tap(find.byKey(const Key('real-light-prompt-switch')));
    await t.pump();
    expect(store.realLightPrompt, isTrue);
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

  // ── Home & wake detection ──────────────────────────────────────────────────

  Future<AppSettings> pumpWithGateway(
      WidgetTester t, HomeLocationGateway gateway,
      {Map<String, Object> initial = const {}}) async {
    SharedPreferences.setMockInitialValues(initial);
    final store = await AppSettings.load();
    await _pump(
        t,
        ProviderScope(
          overrides: [appSettingsProvider.overrideWithValue(store)],
          child: MaterialApp(home: SettingsScreen(homeLocation: gateway)),
        ));
    await t.pump();
    return store;
  }

  /// Drains the toast overlay's ~2.7s auto-dismiss timer + fade-out.
  Future<void> drainToast(WidgetTester t) async {
    await t.pump(const Duration(seconds: 3));
    await t.pump(const Duration(milliseconds: 300));
  }

  testWidgets('setting home persists the fix and shows the accuracy',
      (t) async {
    final gateway = FakeHomeLocationGateway(
        granted: true,
        fix: const HomeFix(
            latitude: 52.52, longitude: 13.405, accuracyMeters: 12));
    final store = await pumpWithGateway(t, gateway);

    await t.tap(find.byKey(const Key('set-home-row')));
    await t.pump();
    await t.pump();

    expect(store.homeLat, 52.52);
    expect(store.homeLng, 13.405);
    expect(gateway.ensurePermissionCalls, 1);
    expect(gateway.currentFixCalls, 1);
    // Warm, honest copy: resolved accuracy + the local-only promise.
    expect(
        find.text('Home set — accurate to about 12 m. It stays on this phone.'),
        findsOneWidget);
    await drainToast(t);
  });

  testWidgets('permission denied degrades to a toast — no crash, nothing saved',
      (t) async {
    final gateway = FakeHomeLocationGateway(granted: false);
    final store = await pumpWithGateway(t, gateway);

    await t.tap(find.byKey(const Key('set-home-row')));
    await t.pump();
    await t.pump();

    expect(store.homeLat, isNull);
    expect(gateway.currentFixCalls, 0); // denied → never reads a location
    expect(find.textContaining('needs location permission'), findsOneWidget);
    await drainToast(t);
  });

  testWidgets('no fix (timeout/services off) shows a toast and saves nothing',
      (t) async {
    final gateway = FakeHomeLocationGateway(granted: true, fix: null);
    final store = await pumpWithGateway(t, gateway);

    await t.tap(find.byKey(const Key('set-home-row')));
    await t.pump();
    await t.pump();

    expect(store.homeLat, isNull);
    expect(find.textContaining('Couldn\'t get a location fix'), findsOneWidget);
    await drainToast(t);
  });

  testWidgets('clear home removes the anchor (row only shows when set)',
      (t) async {
    final gateway = FakeHomeLocationGateway();
    final store = await pumpWithGateway(t, gateway,
        initial: {'homeLat': 52.52, 'homeLng': 13.405});

    expect(find.byKey(const Key('clear-home-row')), findsOneWidget);
    await t.tap(find.byKey(const Key('clear-home-row')));
    await t.pump();
    await t.pump();

    expect(store.homeLat, isNull);
    expect(store.homeLng, isNull);
    expect(find.byKey(const Key('clear-home-row')), findsNothing);
    await drainToast(t);
  });

  testWidgets('clear-home row is hidden while home is unset', (t) async {
    await pumpWithGateway(t, FakeHomeLocationGateway());
    expect(find.byKey(const Key('clear-home-row')), findsNothing);
  });

  testWidgets('home share tier defaults Off and persists a change', (t) async {
    final store = await pumpWithGateway(t, FakeHomeLocationGateway());
    expect(store.homeShare, HomeShareTier.off); // privacy default

    await t.tap(find.text('My crew'));
    await t.pump();
    expect(store.homeShare, HomeShareTier.crew);

    await t.tap(find.text('Just me'));
    await t.pump();
    expect(store.homeShare, HomeShareTier.private);
  });
}
