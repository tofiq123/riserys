import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/native/alarm_api.g.dart';
import 'package:rise/data/permission_gateway.dart';
import 'package:rise/ui/screens/profile_screen.dart';

class _FakeGateway implements PermissionGateway {
  _FakeGateway(this._p);
  final AlarmPermissions _p;
  @override
  Future<AlarmPermissions> status() async => _p;
  @override
  Future<void> requestNotifications() async {}
  @override
  Future<void> openExactAlarm() async {}
  @override
  Future<void> openFullScreenIntent() async {}
  @override
  Future<void> openBattery() async {}
}

// Profile (guest card + reliability's four permission rows + about) is taller
// than flutter_test's default 800x600 logical viewport, so the About section
// would be clipped offstage under the default size — same issue documented in
// create_edit_screen_test.dart. Real phones are taller than 600dp, so
// enlarging the virtual view's height makes the test canvas representative of
// an actual device without altering anything being asserted.
Future<void> _pump(WidgetTester t, Widget widget) async {
  t.view.physicalSize = const Size(2400, 8000);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(widget);
}

void main() {
  testWidgets('shows profile, reliability permissions, and about', (t) async {
    await _pump(
        t,
        MaterialApp(
          home: Scaffold(
            body: ProfileScreen(
              permissions: _FakeGateway(AlarmPermissions(
                  notifications: false,
                  exactAlarm: false,
                  fullScreenIntent: false,
                  batteryUnrestricted: false)),
            ),
          ),
        ));
    await t.pumpAndSettle();
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Guest'), findsOneWidget);
    expect(find.text('Grant'), findsNWidgets(4));
    expect(find.text('1.0.0'), findsOneWidget);
  });
}
