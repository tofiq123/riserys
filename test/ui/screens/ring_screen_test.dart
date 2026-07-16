import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/alarm.dart';
import 'package:rise/ui/components/slide_to_wake.dart';
import 'package:rise/ui/screens/ring_screen.dart';
import 'package:rise/ui/state/alarm_providers.dart';

Widget _host({
  required List<Alarm> alarms,
  required int alarmId,
  Future<void> Function(int)? dismissAlarm,
  VoidCallback? onDismissed,
  MissionBuilder? missionBuilder,
}) {
  return ProviderScope(
    overrides: [alarmsProvider.overrideWith((ref) => Stream.value(alarms))],
    child: MaterialApp(
      home: RingScreen(
        alarmId: alarmId,
        onDismissed: onDismissed,
        dismissAlarm: dismissAlarm ?? (_) async {},
        missionBuilder: missionBuilder,
      ),
    ),
  );
}

void main() {
  testWidgets('no-mission alarm shows slide-to-wake; sliding dismisses', (t) async {
    int? dismissed;
    var doneCalled = false;
    await t.pumpWidget(_host(
      alarms: const [Alarm(id: 5, hour: 6, minute: 30, label: 'Run')],
      alarmId: 5,
      dismissAlarm: (id) async => dismissed = id,
      onDismissed: () => doneCalled = true,
    ));
    await t.pump(); // let alarmsProvider emit
    expect(find.byType(SlideToWake), findsOneWidget);
    await t.drag(find.byType(SlideToWake), const Offset(1000, 0));
    await t.pump();
    await t.pump(const Duration(milliseconds: 20));
    expect(dismissed, 5);
    expect(doneCalled, isTrue);
  });

  testWidgets('shows the alarm label', (t) async {
    await t.pumpWidget(_host(
      alarms: const [Alarm(id: 5, hour: 6, minute: 30, label: 'Gym time')],
      alarmId: 5,
    ));
    await t.pump();
    expect(find.text('Gym time'), findsOneWidget);
  });

  testWidgets('a missioned alarm with a missionBuilder shows the mission, not the slider', (t) async {
    int? dismissed;
    await t.pumpWidget(_host(
      alarms: const [Alarm(id: 7, hour: 6, minute: 30, mission: 'math')],
      alarmId: 7,
      dismissAlarm: (id) async => dismissed = id,
      missionBuilder: (context, alarm, onSolved) =>
          TextButton(onPressed: onSolved, child: const Text('SOLVE')),
    ));
    await t.pump();
    expect(find.byType(SlideToWake), findsNothing);
    expect(find.text('SOLVE'), findsOneWidget);
    await t.tap(find.text('SOLVE'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 20));
    expect(dismissed, 7);
  });

  testWidgets('unknown alarm still shows a slider so the user can dismiss', (t) async {
    await t.pumpWidget(_host(alarms: const [], alarmId: 999));
    await t.pump();
    expect(find.byType(SlideToWake), findsOneWidget);
  });

  testWidgets('a failed dismissal keeps the screen so the user can retry', (t) async {
    var doneCalled = false;
    await t.pumpWidget(_host(
      alarms: const [Alarm(id: 5, hour: 6, minute: 30)],
      alarmId: 5,
      dismissAlarm: (_) async => throw StateError('stop failed'),
      onDismissed: () => doneCalled = true,
    ));
    await t.pump();
    await t.drag(find.byType(SlideToWake), const Offset(1000, 0));
    await t.pump();
    await t.pump(const Duration(milliseconds: 20));
    expect(doneCalled, isFalse);
    expect(find.byType(RingScreen), findsOneWidget);
  });
}
