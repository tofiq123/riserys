import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/screen_brightness_controller.dart';
import 'package:rise/data/wake_recorder.dart';
import 'package:rise/domain/alarm.dart';
import 'package:rise/domain/rise_settings.dart';
import 'package:rise/domain/wake_confidence.dart';
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
  StayUpDecider? stayUpDecision,
  BrightnessController? brightness,
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
        stayUpDecision: stayUpDecision ?? defaultStayUpDecision,
        brightness: brightness ?? const NoopBrightnessController(),
      ),
    ),
  );
}

/// Records brightness calls so tests can assert the sunrise ramp/restore
/// without touching the real plugin.
class _FakeBrightness implements BrightnessController {
  final List<double> sets = [];
  bool restored = false;
  @override
  Future<void> setBrightness(double value) async => sets.add(value);
  @override
  Future<void> restore() async => restored = true;
}

class _RecordingRecorder implements WakeRecorder {
  final opened = <int>[];
  final finalized = <(int, String?)>[];
  int? lastAlertness;
  @override
  void Function()? get onRingOpened => null;
  @override
  Future<void> openRing(int alarmId) async => opened.add(alarmId);
  @override
  Future<void> finalizeDismiss(int alarmId,
      {String? method, int? alertnessScore}) async {
    finalized.add((alarmId, method));
    lastAlertness = alertnessScore;
  }
}

class _ThrowingRecorder implements WakeRecorder {
  @override
  void Function()? get onRingOpened => null;
  @override
  Future<void> openRing(int alarmId) async => throw StateError('wake db down');
  @override
  Future<void> finalizeDismiss(int alarmId,
          {String? method, int? alertnessScore}) async =>
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

  testWidgets('shows the wake plan when one is set, hides it otherwise', (t) async {
    // A realistic phone height: the default 600px test surface is shorter than
    // any modern phone, and a wake plan + the default-on light prompt together
    // need normal room.
    t.view.physicalSize = const Size(800, 1200);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(_host(
      alarms: const [Alarm(id: 5, hour: 6, minute: 30)],
      alarmId: 5,
      settings: const RiseSettings(wakeIntention: 'Put my feet on the floor'),
    ));
    await t.pump();
    expect(find.text('Your plan: Put my feet on the floor'), findsOneWidget);
  });

  testWidgets('no wake plan means no plan reminder', (t) async {
    await t.pumpWidget(_host(
      alarms: const [Alarm(id: 5, hour: 6, minute: 30)],
      alarmId: 5,
    ));
    await t.pump();
    expect(find.textContaining('Your plan:'), findsNothing);
  });

  testWidgets('a missioned alarm with a missionBuilder shows the mission, not the slider', (t) async {
    int? dismissed;
    await t.pumpWidget(_host(
      alarms: const [Alarm(id: 7, hour: 6, minute: 30, mission: 'math')],
      alarmId: 7,
      dismissAlarm: (id) async => dismissed = id,
      missionBuilder: (context, alarm, onSolved, onAlertness) =>
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
          missionBuilder: (context, alarm, onSolved, onAlertness) =>
              _OnceMission(onSolved),
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

  testWidgets('a 2-mission chain requires two completions before dismissal',
      (t) async {
    int? dismissed;
    await t.pumpWidget(_host(
      alarms: const [
        Alarm(id: 7, hour: 6, minute: 30, mission: 'math', missionCount: 2)
      ],
      alarmId: 7,
      dismissAlarm: (id) async => dismissed = id,
      // A fresh solvable button is built on each rebuild (the gate re-keys on
      // each completion), so the same finder solves each rep of the chain.
      missionBuilder: (context, alarm, onSolved, onAlertness) =>
          TextButton(onPressed: onSolved, child: const Text('SOLVE')),
    ));
    await t.pump();
    expect(find.text('1 of 2'), findsOneWidget);
    await t.tap(find.text('SOLVE')); // first of two completions
    await t.pump();
    await t.pump(const Duration(milliseconds: 20));
    expect(dismissed, isNull,
        reason: 'a chain must not dismiss until every rep is done');
    expect(find.text('2 of 2'), findsOneWidget);
    await t.tap(find.text('SOLVE')); // second completion → dismiss
    await t.pump();
    await t.pump(const Duration(milliseconds: 20));
    expect(dismissed, 7);
  });

  // Three clean mission-method dismissals — a "breezing" history.
  List<WakeEvent> breezingHistory(int alarmId) => [
        for (var i = 1; i <= 3; i++)
          WakeEvent(
            id: i,
            alarmId: alarmId,
            scheduledAt: DateTime.utc(2026, 7, 20, 6).subtract(Duration(days: i)),
            firstRingAt: DateTime.utc(2026, 7, 20, 6).subtract(Duration(days: i)),
            dismissedAt:
                DateTime.utc(2026, 7, 20, 6, 1).subtract(Duration(days: i)),
            method: 'mission',
            onTime: true,
          ),
      ];

  testWidgets('adaptive difficulty on: a breezing user is shown a harder mission',
      (t) async {
    String? diffSeen;
    await t.pumpWidget(_host(
      alarms: const [
        Alarm(id: 5, hour: 6, minute: 30, mission: 'math', missionDiff: 'easy')
      ],
      alarmId: 5,
      settings: const RiseSettings(adaptiveMissions: true),
      wakeEvents: breezingHistory(5),
      missionBuilder: (context, alarm, onSolved, onAlertness) {
        diffSeen = alarm.missionDiff;
        return const Text('MISSION');
      },
    ));
    await t.pump();
    expect(diffSeen, 'medium', reason: 'easy bumps one tier when breezing');
  });

  testWidgets('adaptive difficulty off (default): the chosen difficulty is unchanged',
      (t) async {
    String? diffSeen;
    await t.pumpWidget(_host(
      alarms: const [
        Alarm(id: 5, hour: 6, minute: 30, mission: 'math', missionDiff: 'easy')
      ],
      alarmId: 5,
      settings: const RiseSettings(), // adaptiveMissions defaults off
      wakeEvents: breezingHistory(5),
      missionBuilder: (context, alarm, onSolved, onAlertness) {
        diffSeen = alarm.missionDiff;
        return const Text('MISSION');
      },
    ));
    await t.pump();
    expect(diffSeen, 'easy');
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
          missionBuilder: (context, alarm, onSolved, onAlertness) =>
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

  testWidgets('with record: a PVT mission threads its alertness score into finalize',
      (t) async {
    final rec = _RecordingRecorder();
    await t.pumpWidget(ProviderScope(
      overrides: [
        alarmsProvider.overrideWith((ref) => Stream.value(
            const [Alarm(id: 7, hour: 6, minute: 30, mission: 'pvt')])),
        wakeRecorderProvider.overrideWithValue(rec),
        currentSettingsProvider.overrideWithValue(const RiseSettings()),
        wakeEventsProvider.overrideWith((ref) => Stream.value(const <WakeEvent>[])),
      ],
      child: MaterialApp(
        home: RingScreen(
          alarmId: 7,
          record: true,
          dismissAlarm: (_) async {},
          // A stand-in mission that reports a score, then solves — exercises the
          // gate's onAlertness -> _pendingAlertness -> finalizeDismiss path.
          missionBuilder: (context, alarm, onSolved, onAlertness) => TextButton(
            onPressed: () {
              onAlertness?.call(84);
              onSolved();
            },
            child: const Text('SOLVE'),
          ),
          armWakeCheck: (_, __) async {},
        ),
      ),
    ));
    await t.pump();
    await t.tap(find.text('SOLVE'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 20));
    expect(rec.finalized, [(7, 'mission')]);
    expect(rec.lastAlertness, 84);
  });

  testWidgets('with record: a non-PVT mission finalizes with a null alertness score',
      (t) async {
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
        home: RingScreen(
          alarmId: 5,
          record: true,
          dismissAlarm: (_) async {},
          armWakeCheck: (_, __) async {},
        ),
      ),
    ));
    await t.pump();
    await t.drag(find.byType(SlideToWake), const Offset(1000, 0));
    await t.pump();
    await t.pump(const Duration(milliseconds: 20));
    expect(rec.finalized, [(5, 'slide')]);
    expect(rec.lastAlertness, isNull);
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

  // ---- Phase 11: opt-in smart wake-check (stay-up verification) ----

  testWidgets('smart wake-check on: a confident stay-up decision skips the re-ring',
      (t) async {
    var armedCount = 0;
    await t.pumpWidget(_host(
      alarms: const [Alarm(id: 5, hour: 6, minute: 30)],
      alarmId: 5,
      record: true,
      recorder: _RecordingRecorder(),
      settings:
          const RiseSettings(wakeCheckEnabled: true, smartWakeCheck: true),
      stayUpDecision: (_, __, ___) async => WakeChallengeDecision.confident,
      armWakeCheck: (_, __) async => armedCount++,
      onDismissed: () {},
    ));
    await t.pump();
    await t.drag(find.byType(SlideToWake), const Offset(1000, 0));
    await t.pump();
    await t.pump(const Duration(milliseconds: 20));
    expect(armedCount, 0, reason: 'strong stay-up confidence suppresses the re-ring');
  });

  testWidgets(
      'smart wake-check on: a low/unknown decision falls back to the ordinary re-ring',
      (t) async {
    Alarm? armed;
    Duration? delay;
    await t.pumpWidget(_host(
      alarms: const [Alarm(id: 5, hour: 6, minute: 30)],
      alarmId: 5,
      record: true,
      recorder: _RecordingRecorder(),
      settings: const RiseSettings(
          wakeCheckEnabled: true, smartWakeCheck: true, wakeCheckDelayMinutes: 7),
      stayUpDecision: (_, __, ___) async => WakeChallengeDecision.reCheck,
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
    expect(armed?.id, 5); // same alarm, same delay as the ordinary check
    expect(delay, const Duration(minutes: 7));
  });

  testWidgets(
      'smart wake-check on: a failing decider still arms the re-ring (safe default)',
      (t) async {
    var armedCount = 0;
    await t.pumpWidget(_host(
      alarms: const [Alarm(id: 5, hour: 6, minute: 30)],
      alarmId: 5,
      record: true,
      recorder: _RecordingRecorder(),
      settings:
          const RiseSettings(wakeCheckEnabled: true, smartWakeCheck: true),
      stayUpDecision: (_, __, ___) async => throw StateError('sensor down'),
      armWakeCheck: (_, __) async => armedCount++,
      onDismissed: () {},
    ));
    await t.pump();
    await t.drag(find.byType(SlideToWake), const Offset(1000, 0));
    await t.pump();
    await t.pump(const Duration(milliseconds: 20));
    expect(armedCount, 1, reason: 'a sensing failure must never suppress the re-ring');
  });

  testWidgets(
      'smart wake-check off (default): arms immediately and never consults the decider',
      (t) async {
    var armedCount = 0;
    var deciderCalls = 0;
    await t.pumpWidget(_host(
      alarms: const [Alarm(id: 5, hour: 6, minute: 30)],
      alarmId: 5,
      record: true,
      recorder: _RecordingRecorder(),
      settings: const RiseSettings(wakeCheckEnabled: true), // smart defaults off
      stayUpDecision: (_, __, ___) async {
        deciderCalls++;
        return WakeChallengeDecision.confident;
      },
      armWakeCheck: (_, __) async => armedCount++,
      onDismissed: () {},
    ));
    await t.pump();
    await t.drag(find.byType(SlideToWake), const Offset(1000, 0));
    await t.pump();
    await t.pump(const Duration(milliseconds: 20));
    expect(armedCount, 1, reason: 'off = exactly today\'s behavior');
    expect(deciderCalls, 0);
  });

  testWidgets('smart wake-check on: threads the PVT alertness score into the decider',
      (t) async {
    int? seenAlertness;
    await t.pumpWidget(_host(
      alarms: const [Alarm(id: 7, hour: 6, minute: 30, mission: 'pvt')],
      alarmId: 7,
      record: true,
      recorder: _RecordingRecorder(),
      settings:
          const RiseSettings(wakeCheckEnabled: true, smartWakeCheck: true),
      missionBuilder: (context, alarm, onSolved, onAlertness) => TextButton(
        onPressed: () {
          onAlertness?.call(90);
          onSolved();
        },
        child: const Text('SOLVE'),
      ),
      stayUpDecision: (_, __, alertness) async {
        seenAlertness = alertness;
        return WakeChallengeDecision.confident;
      },
      onDismissed: () {},
    ));
    await t.pump();
    await t.tap(find.text('SOLVE'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 20));
    expect(seenAlertness, 90);
  });

  // ---- Phase 10a: opt-in on-screen sunrise wake ----

  testWidgets('sunrise wake on: paints the animated dawn background', (t) async {
    await t.pumpWidget(_host(
      alarms: const [Alarm(id: 5, hour: 6, minute: 30)],
      alarmId: 5,
      settings: const RiseSettings(sunriseWake: true),
    ));
    await t.pump();
    expect(find.byKey(const Key('sunrise-bg')), findsOneWidget);
  });

  testWidgets('sunrise wake off (default): no dawn background', (t) async {
    await t.pumpWidget(_host(
      alarms: const [Alarm(id: 5, hour: 6, minute: 30)],
      alarmId: 5,
    ));
    await t.pump();
    expect(find.byKey(const Key('sunrise-bg')), findsNothing);
  });

  testWidgets('sunrise wake on: ramps brightness on mount, restores on dispose',
      (t) async {
    final fake = _FakeBrightness();
    await t.pumpWidget(_host(
      alarms: const [Alarm(id: 5, hour: 6, minute: 30)],
      alarmId: 5,
      settings: const RiseSettings(sunriseWake: true),
      brightness: fake,
    ));
    await t.pump();
    await t.pump(const Duration(milliseconds: 120)); // let the ramp tick
    expect(fake.sets, isNotEmpty, reason: 'sunrise ramps brightness up');
    expect(fake.restored, isFalse);
    // Tearing the screen down restores the system brightness.
    await t.pumpWidget(const SizedBox());
    await t.pump();
    expect(fake.restored, isTrue);
  });

  testWidgets('sunrise wake off: never touches the brightness controller',
      (t) async {
    final fake = _FakeBrightness();
    await t.pumpWidget(_host(
      alarms: const [Alarm(id: 5, hour: 6, minute: 30)],
      alarmId: 5,
      settings: const RiseSettings(), // sunrise off
      brightness: fake,
    ));
    await t.pump();
    await t.pump(const Duration(milliseconds: 120));
    await t.pumpWidget(const SizedBox());
    await t.pump();
    expect(fake.sets, isEmpty);
    expect(fake.restored, isFalse);
  });

  testWidgets(
      'sunrise wake with reduce-motion: static background, single brightness boost',
      (t) async {
    final fake = _FakeBrightness();
    await t.pumpWidget(ProviderScope(
      overrides: [
        alarmsProvider.overrideWith(
            (ref) => Stream.value(const [Alarm(id: 5, hour: 6, minute: 30)])),
        currentSettingsProvider
            .overrideWithValue(const RiseSettings(sunriseWake: true)),
        wakeEventsProvider
            .overrideWith((ref) => Stream.value(const <WakeEvent>[])),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: RingScreen(alarmId: 5, brightness: fake),
          ),
        ),
      ),
    ));
    await t.pump();
    await t.pump(const Duration(milliseconds: 120));
    expect(find.byKey(const Key('sunrise-bg')), findsOneWidget);
    expect(fake.sets, [1.0],
        reason: 'reduce-motion boosts once to full, no ramp');
  });

  test('sunriseGradient darkens the sky at dawn and brightens toward day', () {
    final dawn = sunriseGradient(0.0);
    final day = sunriseGradient(1.0);
    expect(dawn.colors.length, 4);
    // The top sky stop is much darker at t=0 than at t=1.
    expect(dawn.colors.first.computeLuminance(),
        lessThan(day.colors.first.computeLuminance()));
    // The clock band (3rd stop) stays light at both ends, for legibility.
    expect(dawn.colors[2].computeLuminance(), greaterThan(0.5));
    expect(day.colors[2].computeLuminance(), greaterThan(0.5));
  });

  // ---- Phase 10b: honest "get real light" prompt ----

  testWidgets('real-light prompt shows on the ring when enabled', (t) async {
    await t.pumpWidget(_host(
      alarms: const [Alarm(id: 5, hour: 6, minute: 30)],
      alarmId: 5,
      settings: const RiseSettings(realLightPrompt: true),
    ));
    await t.pump();
    expect(find.textContaining('too dim to fully wake you'), findsOneWidget);
  });

  testWidgets('real-light prompt hidden when disabled', (t) async {
    await t.pumpWidget(_host(
      alarms: const [Alarm(id: 5, hour: 6, minute: 30)],
      alarmId: 5,
      settings: const RiseSettings(realLightPrompt: false),
    ));
    await t.pump();
    expect(find.textContaining('too dim to fully wake you'), findsNothing);
  });

  testWidgets('real-light prompt is dismissible', (t) async {
    await t.pumpWidget(_host(
      alarms: const [Alarm(id: 5, hour: 6, minute: 30)],
      alarmId: 5,
      settings: const RiseSettings(realLightPrompt: true),
    ));
    await t.pump();
    expect(find.textContaining('too dim to fully wake you'), findsOneWidget);
    await t.tap(find.byKey(const Key('light-prompt-dismiss')));
    await t.pump();
    expect(find.textContaining('too dim to fully wake you'), findsNothing);
  });
}
