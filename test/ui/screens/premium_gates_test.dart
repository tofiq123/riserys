import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/app_settings.dart';
import 'package:rise/data/iap/entitlement_service.dart';
import 'package:rise/domain/alarm.dart';
import 'package:rise/ui/screens/create_edit_screen.dart';
import 'package:rise/ui/screens/paywall_screen.dart';
import 'package:rise/ui/screens/settings_screen.dart';
import 'package:rise/ui/state/alarm_providers.dart';
import 'package:rise/ui/state/entitlement_providers.dart';
import 'package:rise/ui/state/settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoopMutations implements AlarmMutations {
  @override
  Future<void> save(Alarm alarm) async {}
  @override
  Future<void> delete(int id) async {}
  @override
  Future<void> setEnabled(int id, bool enabled) async {}
  @override
  Future<void> Function(int alarmId) get cancelWakeCheck => (_) async {};
}

Future<void> _pumpBig(WidgetTester t, Widget w) async {
  t.view.physicalSize = const Size(2400, 8000);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(w);
  await t.pumpAndSettle();
}

Widget _createEditHost(ProviderContainer c) => UncontrolledProviderScope(
      container: c,
      child: MaterialApp(home: Scaffold(body: CreateEditScreen(onDone: () {}))),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Create/Edit mission gates', () {
    testWidgets('premium mission opens the paywall when locked, does not select',
        (t) async {
      final fake = FakeEntitlementService(premium: false);
      addTearDown(fake.dispose);
      final c = ProviderContainer(overrides: [
        alarmMutationsProvider.overrideWithValue(_NoopMutations()),
        entitlementServiceProvider.overrideWithValue(fake),
      ]);
      addTearDown(c.dispose);
      c.read(draftProvider.notifier).startNew();
      await _pumpBig(t, _createEditHost(c));

      await t.tap(find.byKey(const Key('wake-mission-row')));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Type a phrase'));
      await t.tap(find.text('Type a phrase'));
      await t.pumpAndSettle();

      expect(find.byType(PaywallScreen), findsOneWidget);
      expect(c.read(draftProvider)!.mission, isNot('typing'));
    });

    testWidgets('premium mission selects normally when unlocked', (t) async {
      final c = ProviderContainer(overrides: [
        alarmMutationsProvider.overrideWithValue(_NoopMutations()),
        // no entitlement override → UnlockedEntitlementService (graceful unlock)
      ]);
      addTearDown(c.dispose);
      c.read(draftProvider.notifier).startNew();
      await _pumpBig(t, _createEditHost(c));

      await t.tap(find.byKey(const Key('wake-mission-row')));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Type a phrase'));
      await t.tap(find.text('Type a phrase'));
      await t.pump();
      await t.tap(find.text('Done'));
      await t.pumpAndSettle();

      expect(find.byType(PaywallScreen), findsNothing);
      expect(c.read(draftProvider)!.mission, 'typing');
    });

    testWidgets('mission chain (2x) opens the paywall when locked', (t) async {
      final fake = FakeEntitlementService(premium: false);
      addTearDown(fake.dispose);
      final c = ProviderContainer(overrides: [
        alarmMutationsProvider.overrideWithValue(_NoopMutations()),
        entitlementServiceProvider.overrideWithValue(fake),
      ]);
      addTearDown(c.dispose);
      c.read(draftProvider.notifier).startEdit(
          const Alarm(id: 3, hour: 7, minute: 0, mission: 'math'));
      await _pumpBig(t, _createEditHost(c));

      await t.tap(find.byKey(const Key('wake-mission-row')));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('2×'));
      await t.tap(find.text('2×'));
      await t.pumpAndSettle();

      expect(find.byType(PaywallScreen), findsOneWidget);
      expect(c.read(draftProvider)!.missionCount, 1); // unchanged
    });
  });

  group('Settings smart wake-check gate', () {
    testWidgets('opens the paywall and does not persist when locked', (t) async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppSettings.load();
      final fake = FakeEntitlementService(premium: false);
      addTearDown(fake.dispose);
      await _pumpBig(
        t,
        ProviderScope(
          overrides: [
            appSettingsProvider.overrideWithValue(store),
            entitlementServiceProvider.overrideWithValue(fake),
          ],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );

      await t.ensureVisible(find.byKey(const Key('smart-wake-check-switch')));
      await t.tap(find.byKey(const Key('smart-wake-check-switch')));
      await t.pumpAndSettle();

      expect(find.byType(PaywallScreen), findsOneWidget);
      expect(store.smartWakeCheck, isFalse);
    });

    testWidgets('toggles normally when unlocked', (t) async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppSettings.load();
      await _pumpBig(
        t,
        ProviderScope(
          overrides: [appSettingsProvider.overrideWithValue(store)],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );

      await t.ensureVisible(find.byKey(const Key('smart-wake-check-switch')));
      await t.tap(find.byKey(const Key('smart-wake-check-switch')));
      await t.pumpAndSettle();

      expect(find.byType(PaywallScreen), findsNothing);
      expect(store.smartWakeCheck, isTrue);
    });
  });
}
