import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/native/alarm_api.g.dart';
import 'package:rise/data/permission_gateway.dart';
import 'package:rise/ui/screens/onboarding_screen.dart';

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

Widget _host(_FakeGateway gw, {VoidCallback? onDone}) => MaterialApp(
      home: OnboardingScreen(onDone: onDone ?? () {}, permissions: gw),
    );

Future<void> _toPermissions(WidgetTester t) async {
  await t.tap(find.text('Next'));
  await t.pumpAndSettle();
  await t.tap(find.text('Next'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('advances through pages and Start calls onDone', (t) async {
    var done = false;
    await t.pumpWidget(_host(_FakeGateway(_perms()), onDone: () => done = true));
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
    await t.pumpWidget(_host(_FakeGateway(_perms()), onDone: () => done = true));
    await t.pumpAndSettle();
    await t.tap(find.text('Skip'));
    await t.pumpAndSettle();
    expect(done, isTrue);
  });

  testWidgets('ungranted notifications shows Grant; tapping requests and updates',
      (t) async {
    final gw = _FakeGateway(_perms());
    await t.pumpWidget(_host(gw));
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
    await t.pumpWidget(_host(gw));
    await t.pumpAndSettle();
    await _toPermissions(t);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Grant'), findsNWidgets(3)); // three ungranted
  });

  testWidgets('tapping the exact-alarm Grant opens its settings', (t) async {
    final gw = _FakeGateway(_perms());
    await t.pumpWidget(_host(gw));
    await t.pumpAndSettle();
    await _toPermissions(t);
    await t.tap(find.text('Grant').at(1)); // order: notif, exact, fsi, battery
    await t.pumpAndSettle();
    expect(gw.opened, contains('exact'));
  });
}
