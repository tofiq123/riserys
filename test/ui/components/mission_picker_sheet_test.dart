import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/alarm.dart';
import 'package:rise/ui/components/mission_picker_sheet.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

/// A taller virtual view so the whole sheet (mission list + config + Done) is
/// on-stage and tappable, as on a real phone.
Future<void> _pump(WidgetTester t, MissionPickerSheet sheet) async {
  t.view.physicalSize = const Size(1200, 6000);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(_host(sheet));
  await t.pump();
}

MissionPickerSheet _sheet({
  required Alarm initial,
  bool missionsLocked = false,
  bool chainsLocked = false,
  VoidCallback? onOpenPaywall,
  Future<String?> Function()? onRegisterQr,
  Future<String?> Function()? onRegisterPhoto,
  ValueChanged<Alarm>? onConfirm,
  VoidCallback? onCancel,
}) {
  return MissionPickerSheet(
    initial: initial,
    missionsLocked: missionsLocked,
    chainsLocked: chainsLocked,
    onOpenPaywall: onOpenPaywall ?? () {},
    onRegisterQr: onRegisterQr ?? () async => null,
    onRegisterPhoto: onRegisterPhoto ?? () async => null,
    onConfirm: onConfirm ?? (_) {},
    onCancel: onCancel ?? () {},
  );
}

void main() {
  testWidgets('lists every mission with its one-line description', (t) async {
    await _pump(t, _sheet(initial: const Alarm(id: 1, hour: 6, minute: 30)));
    expect(find.text('Math'), findsOneWidget);
    expect(find.text('Solve a quick problem'), findsOneWidget);
    expect(find.text('Alertness (PVT)'), findsOneWidget);
    // Scroll to reach the last mission and confirm it renders.
    await t.scrollUntilVisible(find.text('Keep your eyes open'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Keep your eyes open'), findsOneWidget);
  });

  testWidgets('switching to a different mission clears a registered code',
      (t) async {
    Alarm? confirmed;
    await _pump(
      t,
      _sheet(
        initial: const Alarm(
            id: 1, hour: 6, minute: 30, mission: 'qr', missionData: 'CODE-123'),
        onConfirm: (a) => confirmed = a,
      ),
    );
    // The qr config shows the registered status.
    expect(find.text('Code registered — scan it to dismiss'), findsOneWidget);

    await t.tap(find.text('Math'));
    await t.pump();
    await t.tap(find.text('Done'));
    await t.pump();

    expect(confirmed, isNotNull);
    expect(confirmed!.mission, 'math');
    expect(confirmed!.missionData, isNull); // stale code cleared on switch
  });

  testWidgets('re-selecting the same mission keeps its registration', (t) async {
    Alarm? confirmed;
    await _pump(
      t,
      _sheet(
        initial: const Alarm(
            id: 1, hour: 6, minute: 30, mission: 'qr', missionData: 'CODE-123'),
        onConfirm: (a) => confirmed = a,
      ),
    );
    await t.tap(find.text('Scan a code')); // already selected → no-op
    await t.pump();
    await t.tap(find.text('Done'));
    await t.pump();
    expect(confirmed!.mission, 'qr');
    expect(confirmed!.missionData, 'CODE-123');
  });

  testWidgets('Difficulty shows for math but not for qr', (t) async {
    await _pump(
      t,
      _sheet(initial: const Alarm(id: 1, hour: 6, minute: 30, mission: 'math')),
    );
    expect(find.text('DIFFICULTY'), findsOneWidget);

    await t.tap(find.text('Scan a code'));
    await t.pump();
    expect(find.text('DIFFICULTY'), findsNothing); // qr ignores difficulty
    expect(find.text('Register QR code'), findsOneWidget);
  });

  testWidgets('registering a QR code stores the returned payload', (t) async {
    Alarm? confirmed;
    await _pump(
      t,
      _sheet(
        initial: const Alarm(id: 1, hour: 6, minute: 30, mission: 'qr'),
        onRegisterQr: () async => 'SCAN-9',
        onConfirm: (a) => confirmed = a,
      ),
    );
    expect(find.text('No code yet — any scan will dismiss'), findsOneWidget);

    await t.tap(find.text('Register QR code'));
    await t.pump();
    expect(find.text('Code registered — scan it to dismiss'), findsOneWidget);

    await t.tap(find.text('Done'));
    await t.pump();
    expect(confirmed!.missionData, 'SCAN-9');
  });

  testWidgets('a locked premium mission routes to the paywall, does not select',
      (t) async {
    var paywalls = 0;
    Alarm? confirmed;
    await _pump(
      t,
      _sheet(
        initial: const Alarm(id: 1, hour: 6, minute: 30, mission: 'none'),
        missionsLocked: true,
        onOpenPaywall: () => paywalls++,
        onConfirm: (a) => confirmed = a,
      ),
    );
    // Premium missions carry a lock glyph.
    expect(find.byIcon(Icons.lock_outline), findsWidgets);

    await t.tap(find.text('Type a phrase'));
    await t.pump();
    expect(paywalls, 1);

    await t.tap(find.text('Done'));
    await t.pump();
    expect(confirmed!.mission, 'none'); // unchanged
  });

  testWidgets('a locked chain length routes to the paywall, does not change count',
      (t) async {
    var paywalls = 0;
    Alarm? confirmed;
    await _pump(
      t,
      _sheet(
        initial: const Alarm(id: 1, hour: 6, minute: 30, mission: 'math'),
        chainsLocked: true,
        onOpenPaywall: () => paywalls++,
        onConfirm: (a) => confirmed = a,
      ),
    );
    await t.tap(find.text('2×'));
    await t.pump();
    expect(paywalls, 1);

    await t.tap(find.text('Done'));
    await t.pump();
    expect(confirmed!.missionCount, 1); // unchanged
  });

  testWidgets('Cancel confirms nothing', (t) async {
    var cancelled = false;
    await _pump(
      t,
      _sheet(
        initial: const Alarm(id: 1, hour: 6, minute: 30),
        onCancel: () => cancelled = true,
      ),
    );
    await t.tap(find.text('Cancel'));
    await t.pump();
    expect(cancelled, isTrue);
  });
}
