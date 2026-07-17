import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/wake_recorder.dart';
import 'package:rise/domain/alarm.dart';
import 'package:rise/ui/components/slide_to_wake.dart';
import 'package:rise/ui/screens/ring_screen.dart';
import 'package:rise/ui/state/alarm_providers.dart';
import 'package:rise/ui/state/wake_providers.dart';

class _OnceMission extends StatefulWidget {
  const _OnceMission(this.onSolved);
  final VoidCallback onSolved;
  @override
  State<_OnceMission> createState() => _OnceMissionState();
}

class _OnceMissionState extends State<_OnceMission> {
  bool _solved = false;
  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: () {
          if (_solved) return;
          _solved = true;
          widget.onSolved();
        },
        child: const Text('SOLVE'),
      );
}

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

class _RecordingRecorder implements WakeRecorder {
  final opened = <int>[];
  final finalized = <(int, String?)>[];
  @override
  Future<void> openRing(int alarmId) async => opened.add(alarmId);
  @override
  Future<void> finalizeDismiss(int alarmId, {String? method}) async =>
      finalized.add((alarmId, method));
}

class _ThrowingRecorder implements WakeRecorder {
  @override
  Future<void> openRing(int alarmId) async => throw StateError('wake db down');
  @override
  Future<void> finalizeDismiss(int alarmId, {String? method}) async =>
      throw StateError('wake db down');
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

  testWidgets('a missioned alarm stays solvable after a failed dismissal', (t) async {
    var calls = 0;
    await t.pumpWidget(ProviderScope(
      overrides: [
        alarmsProvider.overrideWith((ref) => Stream.value(
            const [Alarm(id: 7, hour: 6, minute: 30, mission: 'math')])),
      ],
      child: MaterialApp(
        home: RingScreen(
          alarmId: 7,
          dismissAlarm: (_) async {
            calls++;
            if (calls == 1) throw StateError('stop failed');
          },
          missionBuilder: (context, alarm, onSolved) => _OnceMission(onSolved),
          onDismissed: () {},
        ),
      ),
    ));
    await t.pump();
    await t.tap(find.text('SOLVE')); // first solve → dismiss throws → mission resets
    await t.pump();
    await t.pump(const Duration(milliseconds: 20));
    expect(calls, 1);
    await t.tap(find.text('SOLVE')); // retry must be possible on the fresh mission
    await t.pump();
    await t.pump(const Duration(milliseconds: 20));
    expect(calls, 2);
  });

  testWidgets('with record: opens on mount and finalizes "slide" on a slide dismiss',
      (t) async {
    final rec = _RecordingRecorder();
    await t.pumpWidget(ProviderScope(
      overrides: [
        alarmsProvider.overrideWith((ref) => Stream.value(
            const [Alarm(id: 5, hour: 6, minute: 30, label: 'Run')])),
        wakeRecorderProvider.overrideWithValue(rec),
      ],
      child: MaterialApp(
        home: RingScreen(alarmId: 5, record: true, dismissAlarm: (_) async {}),
      ),
    ));
    await t.pump();
    expect(rec.opened, [5]);
    await t.drag(find.byType(SlideToWake), const Offset(1000, 0));
    await t.pump();
    await t.pump(const Duration(milliseconds: 20));
    expect(rec.finalized, [(5, 'slide')]);
  });

  testWidgets('with record: a missioned dismiss finalizes with method "mission"',
      (t) async {
    final rec = _RecordingRecorder();
    await t.pumpWidget(ProviderScope(
      overrides: [
        alarmsProvider.overrideWith((ref) => Stream.value(
            const [Alarm(id: 7, hour: 6, minute: 30, mission: 'math')])),
        wakeRecorderProvider.overrideWithValue(rec),
      ],
      child: MaterialApp(
        home: RingScreen(
          alarmId: 7,
          record: true,
          dismissAlarm: (_) async {},
          missionBuilder: (context, alarm, onSolved) =>
              TextButton(onPressed: onSolved, child: const Text('SOLVE')),
        ),
      ),
    ));
    await t.pump();
    expect(rec.opened, [7]);
    await t.tap(find.text('SOLVE'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 20));
    expect(rec.finalized, [(7, 'mission')]);
  });

  testWidgets('without record (default): never touches the wake recorder', (t) async {
    final rec = _RecordingRecorder();
    await t.pumpWidget(ProviderScope(
      overrides: [
        alarmsProvider.overrideWith((ref) => Stream.value(
            const [Alarm(id: 5, hour: 6, minute: 30)])),
        wakeRecorderProvider.overrideWithValue(rec),
      ],
      child: MaterialApp(
        home: RingScreen(alarmId: 5, dismissAlarm: (_) async {}),
      ),
    ));
    await t.pump();
    await t.drag(find.byType(SlideToWake), const Offset(1000, 0));
    await t.pump();
    await t.pump(const Duration(milliseconds: 20));
    expect(rec.opened, isEmpty);
    expect(rec.finalized, isEmpty);
  });

  testWidgets('a failing wake recorder never blocks dismissal (best-effort)', (t) async {
    var done = false;
    await t.pumpWidget(ProviderScope(
      overrides: [
        alarmsProvider.overrideWith((ref) =>
            Stream.value(const [Alarm(id: 5, hour: 6, minute: 30)])),
        wakeRecorderProvider.overrideWithValue(_ThrowingRecorder()),
      ],
      child: MaterialApp(
        home: RingScreen(
          alarmId: 5,
          record: true,
          dismissAlarm: (_) async {},
          onDismissed: () => done = true,
        ),
      ),
    ));
    await t.pump(); // openRing throws internally, is caught — screen is fine
    await t.drag(find.byType(SlideToWake), const Offset(1000, 0));
    await t.pump();
    await t.pump(const Duration(milliseconds: 20));
    expect(done, isTrue); // finalize threw, was caught — onDismissed still fired
  });
}
