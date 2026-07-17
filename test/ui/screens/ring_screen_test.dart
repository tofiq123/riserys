import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/wake_recorder.dart';
import 'package:rise/domain/alarm.dart';
import 'package:rise/domain/rise_settings.dart';
import 'package:rise/domain/wake_event.dart';
import 'package:rise/ui/components/slide_to_wake.dart';
import 'package:rise/ui/screens/ring_screen.dart';
import 'package:rise/ui/state/alarm_providers.dart';
import 'package:rise/ui/state/settings_providers.dart';
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
  RiseSettings settings = const RiseSettings(),
  List<WakeEvent> wakeEvents = const [],
  Future<void> Function(int, Duration)? snooze,
  bool record = false,
  WakeRecorder? recorder,
  Future<void> Function(Alarm, Duration)? armWakeCheck,
}) {
  return ProviderScope(
    overrides: [
      alarmsProvider.overrideWith((ref) => Stream.value(alarms)),
      currentSettingsProvider.overrideWithValue(settings),
      wakeEventsProvider.overrideWith((ref) => Stream.value(wakeEvents)),
      if (recorder != null) wakeRecorderProvider.overrideWithValue(recorder),
    ],
    child: MaterialApp(
      home: RingScreen(
        alarmId: alarmId,
        onDismissed: onDismissed,
        dismissAlarm: dismissAlarm ?? (_) async {},
        missionBuilder: missionBuilder,
        snooze: snooze ?? (_, __) async {},
        record: record,
        armWakeCheck: armWakeCheck ?? (_, __) async {},
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
        currentSettingsProvider.overrideWithValue(const RiseSettings()),
        wakeEventsProvider.overrideWith((ref) => Stream.value(const <WakeEvent>[])),
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
        currentSettingsProvider.overrideWithValue(const RiseSettings()),
        wakeEventsProvider.overrideWith((ref) => Stream.value(const <WakeEvent>[])),
      ],
      child: MaterialApp(
        home: RingScreen(
          alarmId: 5,
          record: true,
          dismissAlarm: (_) async {},
          armWakeCheck: (_, __) async {},
        ),
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
        currentSettingsProvider.overrideWithValue(const RiseSettings()),
        wakeEventsProvider.overrideWith((ref) => Stream.value(const <WakeEvent>[])),
      ],
      child: MaterialApp(
        home: RingScreen(
          alarmId: 7,
          record: true,
          dismissAlarm: (_) async {},
          missionBuilder: (context, alarm, onSolved) =>
              TextButton(onPressed: onSolved, child: const Text('SOLVE')),
          armWakeCheck: (_, __) async {},
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
        currentSettingsProvider.overrideWithValue(const RiseSettings()),
        wakeEventsProvider.overrideWith((ref) => Stream.value(const <WakeEvent>[])),
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
        currentSettingsProvider.overrideWithValue(const RiseSettings()),
        wakeEventsProvider.overrideWith((ref) => Stream.value(const <WakeEvent>[])),
      ],
      child: MaterialApp(
        home: RingScreen(
          alarmId: 5,
          record: true,
          dismissAlarm: (_) async {},
          onDismissed: () => done = true,
          armWakeCheck: (_, __) async {},
        ),
      ),
    ));
    await t.pump(); // openRing throws internally, is caught — screen is fine
    await t.drag(find.byType(SlideToWake), const Offset(1000, 0));
    await t.pump();
    await t.pump(const Duration(milliseconds: 20));
    expect(done, isTrue); // finalize threw, was caught — onDismissed still fired
  });

  WakeEvent openEvent(int alarmId, int snoozeCount) => WakeEvent(
        id: 1,
        alarmId: alarmId,
        scheduledAt: DateTime.utc(2026, 7, 20, 6),
        firstRingAt: DateTime.utc(2026, 7, 20, 6),
        snoozeCount: snoozeCount,
      );

  testWidgets('shows a Snooze button and snoozes for the budget duration', (t) async {
    int? snoozedId;
    Duration? snoozedDur;
    await t.pumpWidget(_host(
      alarms: const [Alarm(id: 5, hour: 6, minute: 30)],
      alarmId: 5,
      settings: const RiseSettings(snoozeMaxCount: 3),
      snooze: (id, d) async {
        snoozedId = id;
        snoozedDur = d;
      },
      onDismissed: () {},
    ));
    await t.pump();
    expect(find.text('Snooze 9 min'), findsOneWidget); // first snooze = 9 min
    await t.tap(find.text('Snooze 9 min'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 20));
    expect(snoozedId, 5);
    expect(snoozedDur, const Duration(minutes: 9));
  });

  testWidgets('the snooze duration shrinks with the open event snooze count', (t) async {
    await t.pumpWidget(_host(
      alarms: const [Alarm(id: 5, hour: 6, minute: 30)],
      alarmId: 5,
      settings: const RiseSettings(snoozeMaxCount: 3),
      wakeEvents: [openEvent(5, 2)], // already snoozed twice
      snooze: (_, __) async {},
    ));
    await t.pump();
    expect(find.text('Snooze 3 min'), findsOneWidget); // 3rd snooze (index 2)
  });

  testWidgets('hides the Snooze button at the budget cap', (t) async {
    await t.pumpWidget(_host(
      alarms: const [Alarm(id: 5, hour: 6, minute: 30)],
      alarmId: 5,
      settings: const RiseSettings(snoozeMaxCount: 2),
      wakeEvents: [openEvent(5, 2)], // at the cap
      snooze: (_, __) async {},
    ));
    await t.pump();
    expect(find.textContaining('Snooze'), findsNothing);
  });

  testWidgets('snoozeMaxCount 0 hides the Snooze button entirely', (t) async {
    await t.pumpWidget(_host(
      alarms: const [Alarm(id: 5, hour: 6, minute: 30)],
      alarmId: 5,
      settings: const RiseSettings(snoozeMaxCount: 0),
      snooze: (_, __) async {},
    ));
    await t.pump();
    expect(find.textContaining('Snooze'), findsNothing);
  });

  testWidgets('record + wake-check enabled arms the check on dismiss', (t) async {
    Alarm? armed;
    Duration? delay;
    await t.pumpWidget(_host(
      alarms: const [Alarm(id: 5, hour: 6, minute: 30)],
      alarmId: 5,
      record: true,
      recorder: _RecordingRecorder(),
      settings: const RiseSettings(wakeCheckEnabled: true, wakeCheckDelayMinutes: 5),
      armWakeCheck: (a, d) async {
        armed = a;
        delay = d;
      },
      onDismissed: () {},
    ));
    await t.pump();
    await t.drag(find.byType(SlideToWake), const Offset(1000, 0));
    await t.pump();
    await t.pump(const Duration(milliseconds: 20));
    expect(armed?.id, 5);
    expect(delay, const Duration(minutes: 5));
  });

  testWidgets('wake-check disabled does not arm the check', (t) async {
    var armedCount = 0;
    await t.pumpWidget(_host(
      alarms: const [Alarm(id: 5, hour: 6, minute: 30)],
      alarmId: 5,
      record: true,
      recorder: _RecordingRecorder(),
      settings: const RiseSettings(wakeCheckEnabled: false),
      armWakeCheck: (_, __) async {
        armedCount++;
      },
      onDismissed: () {},
    ));
    await t.pump();
    await t.drag(find.byType(SlideToWake), const Offset(1000, 0));
    await t.pump();
    await t.pump(const Duration(milliseconds: 20));
    expect(armedCount, 0);
  });

  testWidgets('a preview dismissal (record false) does not arm the check', (t) async {
    var armedCount = 0;
    await t.pumpWidget(_host(
      alarms: const [Alarm(id: 5, hour: 6, minute: 30)],
      alarmId: 5,
      settings: const RiseSettings(wakeCheckEnabled: true),
      armWakeCheck: (_, __) async {
        armedCount++;
      },
      onDismissed: () {},
    ));
    await t.pump();
    await t.drag(find.byType(SlideToWake), const Offset(1000, 0));
    await t.pump();
    await t.pump(const Duration(milliseconds: 20));
    expect(armedCount, 0);
  });
}
