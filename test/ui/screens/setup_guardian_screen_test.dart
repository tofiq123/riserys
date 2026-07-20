import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/device_info_gateway.dart';
import 'package:rise/data/native/alarm_api.g.dart';
import 'package:rise/data/permission_gateway.dart';
import 'package:rise/ui/screens/setup_guardian_screen.dart';

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

class _FakeDeviceInfo implements DeviceInfoGateway {
  _FakeDeviceInfo({this.android = true, this.manufacturer = 'samsung'});
  final bool android;
  final String? manufacturer;
  @override
  bool get isAndroid => android;
  @override
  Future<String?> androidManufacturer() async =>
      android ? manufacturer : null;
}

Future<void> _pump(
  WidgetTester t,
  _FakeGateway gw, {
  _FakeDeviceInfo? device,
}) async {
  // The dashboard is taller than the default 800x600 test viewport; enlarge it
  // so the OEM row and Re-check button aren't clipped offstage.
  t.view.physicalSize = const Size(2400, 9000);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    home: SetupGuardianScreen(
      permissions: gw,
      deviceInfo: device ?? _FakeDeviceInfo(),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('all granted on Android: score 100 and no Fix buttons', (t) async {
    final gw = _FakeGateway(_perms(notif: true, exact: true, fsi: true, batt: true));
    await _pump(t, gw);
    expect(find.byKey(const Key('guardian-summary')), findsOneWidget);
    expect(find.text('100'), findsOneWidget);
    // Four granted checks + OEM (unknown) → no "Fix", only OEM "How to fix".
    expect(find.text('Fix'), findsNothing);
    expect(find.text('How to fix'), findsOneWidget);
  });

  testWidgets('ungranted permissions show Fix; headline counts them', (t) async {
    final gw = _FakeGateway(_perms());
    await _pump(t, gw);
    // notifications, exact, full-screen, battery all need attention → 4 Fix.
    expect(find.text('Fix'), findsNWidgets(4));
    expect(find.text('4 things need attention'), findsOneWidget);
  });

  testWidgets('tapping notifications Fix requests and refreshes', (t) async {
    final gw = _FakeGateway(_perms());
    await _pump(t, gw);
    expect(find.text('Fix'), findsNWidgets(4));
    await t.tap(find.text('Fix').first); // notifications is first
    await t.pumpAndSettle();
    expect(gw.notifRequests, 1);
    // Notifications now granted → one fewer Fix, one fewer to attend to.
    expect(find.text('Fix'), findsNWidgets(3));
    expect(find.text('3 things need attention'), findsOneWidget);
  });

  testWidgets('tapping the exact-alarm Fix opens its settings', (t) async {
    final gw = _FakeGateway(_perms());
    await _pump(t, gw);
    // Order: notif, exact, fsi, battery.
    await t.tap(find.text('Fix').at(1));
    await t.pumpAndSettle();
    expect(gw.opened, contains('exact'));
  });

  testWidgets('OEM row expands to manufacturer-specific steps', (t) async {
    final gw = _FakeGateway(_perms(notif: true, exact: true, fsi: true, batt: true));
    await _pump(t, gw, device: _FakeDeviceInfo(manufacturer: 'samsung'));
    // Collapsed by default.
    expect(find.textContaining('Never sleeping apps'), findsNothing);
    await t.tap(find.text('How to fix'));
    await t.pumpAndSettle();
    expect(find.text('SAMSUNG'), findsOneWidget);
    expect(find.textContaining('Never sleeping apps'), findsOneWidget);
    expect(find.text('Open battery settings'), findsOneWidget);
  });

  testWidgets('non-Android hides the battery and OEM rows', (t) async {
    final gw = _FakeGateway(_perms(notif: true, exact: true, fsi: true));
    await _pump(t, gw, device: _FakeDeviceInfo(android: false));
    expect(find.byKey(const Key('guardian-check-battery')), findsNothing);
    expect(find.byKey(const Key('guardian-check-oemAutostart')), findsNothing);
    // Three cross-platform checks remain, all ok → all set.
    expect(find.text('You\'re all set'), findsOneWidget);
  });

  testWidgets('Re-check re-reads status', (t) async {
    final gw = _FakeGateway(_perms());
    await _pump(t, gw);
    // Simulate the user granting battery elsewhere, then Re-check.
    gw.status().then((p) => p.batteryUnrestricted = true);
    await t.pumpAndSettle();
    await t.tap(find.text('Re-check'));
    await t.pumpAndSettle();
    expect(find.text('3 things need attention'), findsOneWidget);
  });
}
