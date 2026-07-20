import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/app_settings.dart';
import 'package:rise/data/native/alarm_api.g.dart';
import 'package:rise/data/permission_gateway.dart';
import 'package:rise/ui/screens/onboarding_screen.dart';
import 'package:rise/ui/state/settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

AlarmPermissions _perms({
  bool notif = false,
  bool exact = false,
  bool fsi = false,
  bool batt = false,
}) =>
    AlarmPermissions(
        notifications: notif,
        exactAlarm: exact,
        fullScreenIntent: fsi,
        batteryUnrestricted: batt);

class _FakeGateway implements PermissionGateway {
  _FakeGateway(this._p);
  final AlarmPermissions _p;
  int notifRequests = 0;
  final opened = <String>[];
  @override
  Future<AlarmPermissions> status() async => _p;
  @override
  Future<void> requestNotifications() async {
    notifRequests++;
    _p.notifications = true;
  }

  @override
  Future<void> openExactAlarm() async => opened.add('exact');
  @override
  Future<void> openFullScreenIntent() async => opened.add('fsi');
  @override
  Future<void> openBattery() async => opened.add('battery');
}

Future<AppSettings> _newStore() async {
  SharedPreferences.setMockInitialValues({});
  return AppSettings.load();
}

Widget _host(_FakeGateway gw, AppSettings store, {VoidCallback? onDone}) =>
    ProviderScope(
      overrides: [appSettingsProvider.overrideWithValue(store)],
      child: MaterialApp(
        home: OnboardingScreen(onDone: onDone ?? () {}, permissions: gw),
      ),
    );

/// Advances from the first page to the permissions page (the last of five).
Future<void> _toPermissions(WidgetTester t) async {
  for (var i = 0; i < 4; i++) {
    await t.tap(find.text('Next'));
    await t.pumpAndSettle();
  }
}

void main() {
  testWidgets('advances through pages and Start calls onDone', (t) async {
    var done = false;
    final store = await _newStore();
    await t.pumpWidget(
        _host(_FakeGateway(_perms()), store, onDone: () => done = true));
    await t.pumpAndSettle();
    expect(find.text('Wake up, for real'), findsOneWidget);
    await _toPermissions(t);
    expect(find.text('Ring through anything'), findsOneWidget);
    await t.tap(find.text('Start using Rise'));
    await t.pumpAndSettle();
    expect(done, isTrue);
  });

  testWidgets('Skip on the first page calls onDone', (t) async {
    var done = false;
    final store = await _newStore();
    await t.pumpWidget(
        _host(_FakeGateway(_perms()), store, onDone: () => done = true));
    await t.pumpAndSettle();
    await t.tap(find.text('Skip'));
    await t.pumpAndSettle();
    expect(done, isTrue);
  });

  testWidgets('the intention step persists a typed plan on finish', (t) async {
    var done = false;
    final store = await _newStore();
    await t.pumpWidget(
        _host(_FakeGateway(_perms()), store, onDone: () => done = true));
    await t.pumpAndSettle();
    // Wake -> Mission -> Intention (page index 2).
    await t.tap(find.text('Next'));
    await t.pumpAndSettle();
    await t.tap(find.text('Next'));
    await t.pumpAndSettle();
    expect(find.text('Make a tiny plan'), findsOneWidget);
    await t.enterText(
        find.byKey(const Key('intention-field')), 'Walk to the kitchen');
    await t.pump();
    // Intention -> Sleep goal -> Permissions -> finish.
    await t.tap(find.text('Next'));
    await t.pumpAndSettle();
    await t.tap(find.text('Next'));
    await t.pumpAndSettle();
    await t.tap(find.text('Start using Rise'));
    await t.pumpAndSettle();
    expect(done, isTrue);
    expect(store.wakeIntention, 'Walk to the kitchen');
  });

  testWidgets('a suggestion chip fills the intention field', (t) async {
    final store = await _newStore();
    await t.pumpWidget(_host(_FakeGateway(_perms()), store));
    await t.pumpAndSettle();
    await t.tap(find.text('Next'));
    await t.pumpAndSettle();
    await t.tap(find.text('Next'));
    await t.pumpAndSettle();
    await t.tap(find.text('Stand up and stretch'));
    await t.pump();
    // Intention -> Sleep goal -> Permissions -> finish persists the chip's text.
    await t.tap(find.text('Next'));
    await t.pumpAndSettle();
    await t.tap(find.text('Next'));
    await t.pumpAndSettle();
    await t.tap(find.text('Start using Rise'));
    await t.pumpAndSettle();
    expect(store.wakeIntention, 'Stand up and stretch');
  });

  testWidgets('opting into a steady wake time persists it on finish', (t) async {
    final store = await _newStore();
    await t.pumpWidget(_host(_FakeGateway(_perms()), store));
    await t.pumpAndSettle();
    // Wake -> Mission -> Intention -> Sleep goal (page index 3).
    for (var i = 0; i < 3; i++) {
      await t.tap(find.text('Next'));
      await t.pumpAndSettle();
    }
    expect(find.text('Aim for a steady wake time'), findsOneWidget);
    // Opt in — reveals the dial seeded at 7:00 AM.
    await t.tap(find.byKey(const Key('sleep-goal-add')));
    await t.pumpAndSettle();
    // Sleep goal -> Permissions -> finish.
    await t.tap(find.text('Next'));
    await t.pumpAndSettle();
    await t.tap(find.text('Start using Rise'));
    await t.pumpAndSettle();
    expect(store.targetWakeHour, 7);
    expect(store.targetWakeMinute, 0);
  });

  testWidgets('skipping leaves the steady wake time unset', (t) async {
    final store = await _newStore();
    await t.pumpWidget(_host(_FakeGateway(_perms()), store));
    await t.pumpAndSettle();
    await t.tap(find.text('Skip'));
    await t.pumpAndSettle();
    expect(store.targetWakeHour, isNull);
    expect(store.targetWakeMinute, isNull);
  });

  testWidgets('skipping leaves the intention unset', (t) async {
    final store = await _newStore();
    await t.pumpWidget(_host(_FakeGateway(_perms()), store));
    await t.pumpAndSettle();
    await t.tap(find.text('Skip'));
    await t.pumpAndSettle();
    expect(store.wakeIntention, '');
  });

  testWidgets('ungranted notifications shows Grant; tapping requests and updates',
      (t) async {
    final gw = _FakeGateway(_perms());
    final store = await _newStore();
    await t.pumpWidget(_host(gw, store));
    await t.pumpAndSettle();
    await _toPermissions(t);
    expect(find.text('Grant'), findsNWidgets(4)); // all four ungranted
    await t.tap(find.text('Grant').first); // notifications is first
    await t.pumpAndSettle();
    expect(gw.notifRequests, 1);
    expect(find.text('Grant'), findsNWidgets(3)); // notifications now granted
  });

  testWidgets('a granted permission shows no Grant button', (t) async {
    final gw = _FakeGateway(_perms(notif: true));
    final store = await _newStore();
    await t.pumpWidget(_host(gw, store));
    await t.pumpAndSettle();
    await _toPermissions(t);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Grant'), findsNWidgets(3)); // three ungranted
  });

  testWidgets('tapping the exact-alarm Grant opens its settings', (t) async {
    final gw = _FakeGateway(_perms());
    final store = await _newStore();
    await t.pumpWidget(_host(gw, store));
    await t.pumpAndSettle();
    await _toPermissions(t);
    await t.tap(find.text('Grant').at(1)); // order: notif, exact, fsi, battery
    await t.pumpAndSettle();
    expect(gw.opened, contains('exact'));
  });
}
