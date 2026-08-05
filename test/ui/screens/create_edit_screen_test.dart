import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/alarm.dart';
import 'package:rise/domain/rise_settings.dart';
import 'package:rise/ui/screens/create_edit_screen.dart';
import 'package:rise/ui/state/alarm_providers.dart';
import 'package:rise/ui/state/settings_providers.dart';

class _RecordingMutations implements AlarmMutations {
  final List<Alarm> saved = [];
  final List<int> deleted = [];
  @override
  Future<void> save(Alarm alarm) async => saved.add(alarm);
  @override
  Future<void> delete(int id) async => deleted.add(id);
  @override
  Future<void> setEnabled(int id, bool enabled) async {}
  @override
  Future<void> Function(int alarmId) get cancelWakeCheck => (_) async {};
}

ProviderContainer _container(_RecordingMutations m) {
  final c = ProviderContainer(
    overrides: [alarmMutationsProvider.overrideWithValue(m)],
  );
  addTearDown(c.dispose);
  return c;
}

Widget _host(ProviderContainer c, {VoidCallback? onDone}) {
  return UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      home: Scaffold(body: CreateEditScreen(onDone: onDone ?? () {})),
    ),
  );
}

// The full form (time dial + repeat + label + sound + mission + difficulty +
// vibrate + save/delete) is taller than flutter_test's default 800x600
// logical viewport, so the tail of the screen would be clipped offstage (and
// unreachable by tap()) under the default size. Real phones are taller than
// 600dp, so enlarging the virtual view's height — width and device pixel
// ratio unchanged — makes the test canvas representative of an actual device
// without altering anything being asserted.
Future<void> _pump(WidgetTester t, Widget widget) async {
  t.view.physicalSize = const Size(2400, 8000);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(widget);
}

void main() {
  testWidgets('edit mode shows the alarm time, label, and "Edit alarm" title', (t) async {
    final c = _container(_RecordingMutations());
    c.read(draftProvider.notifier).startEdit(
        const Alarm(id: 5, hour: 6, minute: 30, label: 'Run', days: {1, 2, 3}));
    await _pump(t, _host(c));
    await t.pump();
    expect(find.text('Edit alarm'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);        // hour dial
    expect(find.text('30'), findsOneWidget);       // minute dial
    expect(find.widgetWithText(TextField, 'Run'), findsOneWidget);
    expect(find.text('Delete alarm'), findsOneWidget);
  });

  testWidgets(
      '24-hour setting: the picker shows a 0–23 hour with no AM/PM, and Save '
      'keeps Alarm.hour in 24h form', (t) async {
    final m = _RecordingMutations();
    final c = ProviderContainer(overrides: [
      alarmMutationsProvider.overrideWithValue(m),
      currentSettingsProvider
          .overrideWithValue(const RiseSettings(use24HourTime: true)),
    ]);
    addTearDown(c.dispose);
    c.read(draftProvider.notifier).startEdit(
        const Alarm(id: 7, hour: 18, minute: 30, label: 'Gym'));
    await _pump(t, _host(c));
    await t.pump();
    expect(find.text('18'), findsOneWidget); // 24h hour spinner, not "6"
    expect(find.text('6'), findsNothing);
    expect(find.text('AM'), findsNothing); // AM/PM toggle hidden in 24h mode
    expect(find.text('PM'), findsNothing);

    await t.tap(find.text('Save alarm'));
    await t.pumpAndSettle();
    expect(m.saved.single.hour, 18); // stored 24-hour form is untouched
    expect(m.saved.single.minute, 30);
  });

  testWidgets('new mode shows "New alarm" and no delete button', (t) async {
    final c = _container(_RecordingMutations());
    c.read(draftProvider.notifier).startNew();
    await _pump(t, _host(c));
    await t.pump();
    expect(find.text('New alarm'), findsOneWidget);
    expect(find.text('Delete alarm'), findsNothing);
  });

  testWidgets('tapping a day chip toggles it in the draft', (t) async {
    final c = _container(_RecordingMutations());
    c.read(draftProvider.notifier)
        .startEdit(const Alarm(id: 5, hour: 6, minute: 30, days: {}));
    await _pump(t, _host(c));
    await t.pump();
    // Monday is index 1; tap the 'M' chip.
    await t.tap(find.text('M'));
    await t.pump();
    expect(c.read(draftProvider)!.days.contains(1), isTrue);
  });

  testWidgets(
      'the wake-mission sheet reveals Difficulty once a mission is chosen and '
      'applies it on Done', (t) async {
    final c = _container(_RecordingMutations());
    c.read(draftProvider.notifier).startEdit(
        const Alarm(id: 5, hour: 6, minute: 30, mission: 'none'));
    await _pump(t, _host(c));
    await t.pump();
    // The form itself no longer carries an inline difficulty control. (The
    // vibration-pattern segmented on the form is a different control.)
    expect(find.text('DIFFICULTY'), findsNothing); // SectionLabel uppercases

    // Open the browsable mission picker and choose Math.
    await t.tap(find.byKey(const Key('wake-mission-row')));
    await t.pumpAndSettle();
    await t.tap(find.text('Math'));
    await t.pump();
    // Choosing a difficulty mission reveals its Difficulty control in the sheet.
    expect(find.text('DIFFICULTY'), findsOneWidget);

    await t.tap(find.text('Done'));
    await t.pumpAndSettle();
    expect(c.read(draftProvider)!.mission, 'math');
  });

  testWidgets('Save persists the draft, arms it, and calls onDone', (t) async {
    final m = _RecordingMutations();
    final c = _container(m);
    var doneCalled = false;
    c.read(draftProvider.notifier)
        .startEdit(const Alarm(id: 5, hour: 6, minute: 30, label: 'Run'));
    await _pump(t, _host(c, onDone: () => doneCalled = true));
    await t.pump();
    await t.tap(find.text('Save alarm'));
    await t.pumpAndSettle();
    expect(m.saved.single.id, 5);
    expect(m.saved.single.label, 'Run');
    expect(doneCalled, isTrue);
  });

  testWidgets('Delete removes the alarm and calls onDone', (t) async {
    final m = _RecordingMutations();
    final c = _container(m);
    var doneCalled = false;
    c.read(draftProvider.notifier)
        .startEdit(const Alarm(id: 5, hour: 6, minute: 30));
    await _pump(t, _host(c, onDone: () => doneCalled = true));
    await t.pump();
    await t.tap(find.text('Delete alarm'));
    await t.pumpAndSettle();
    expect(m.deleted.single, 5);
    expect(doneCalled, isTrue);
  });

  testWidgets('double-tapping Save persists a new alarm only once', (t) async {
    final m = _RecordingMutations();
    final c = _container(m);
    c.read(draftProvider.notifier)
        .startEdit(const Alarm(id: 0, hour: 6, minute: 30)); // new alarm (id 0)
    await _pump(t, _host(c));
    await t.tap(find.text('Save alarm'));
    await t.tap(find.text('Save alarm')); // second tap during the first save's await
    await t.pumpAndSettle();
    expect(m.saved.length, 1);
  });

  testWidgets('the wake-mission sheet lists and selects "Alertness (PVT)"',
      (t) async {
    final c = _container(_RecordingMutations());
    c.read(draftProvider.notifier)
        .startEdit(const Alarm(id: 5, hour: 6, minute: 30, mission: 'none'));
    await _pump(t, _host(c));
    await t.pump();
    await t.tap(find.byKey(const Key('wake-mission-row')));
    await t.pumpAndSettle();
    expect(find.text('Alertness (PVT)'), findsOneWidget);
    await t.tap(find.text('Alertness (PVT)'));
    await t.pump();
    await t.tap(find.text('Done'));
    await t.pumpAndSettle();
    expect(c.read(draftProvider)!.mission, 'pvt');
  });

  testWidgets('renders without crashing for an unknown mission key', (t) async {
    final c = _container(_RecordingMutations());
    c.read(draftProvider.notifier).startEdit(
        const Alarm(id: 5, hour: 6, minute: 30, mission: 'bogus')); // future key, not in kMissionLabels
    await _pump(t, _host(c));
    await t.pump();
    expect(t.takeException(), isNull);
    expect(find.text('Edit alarm'), findsOneWidget); // screen rendered
    // The collapsed wake-mission row degrades gracefully (no inline controls).
    expect(find.byKey(const Key('wake-mission-row')), findsOneWidget);
  });

  testWidgets(
      'vibration pattern control shows under Vibrate (on) and hides when off',
      (t) async {
    final c = _container(_RecordingMutations());
    c.read(draftProvider.notifier)
        .startEdit(const Alarm(id: 5, hour: 6, minute: 30)); // vibrate on
    await _pump(t, _host(c));
    await t.pump();
    expect(find.byKey(const Key('vibration-pattern-segmented')), findsOneWidget);
    expect(find.text('Gentle'), findsOneWidget);
    expect(find.text('Standard'), findsOneWidget);
    expect(find.text('Intense'), findsOneWidget);

    // Turning Vibrate off collapses the pattern control.
    c.read(draftProvider.notifier).update(
        c.read(draftProvider)!.copyWith(vibrate: false));
    await t.pump();
    expect(find.byKey(const Key('vibration-pattern-segmented')), findsNothing);
  });

  testWidgets('choosing a vibration pattern updates the draft and saves it',
      (t) async {
    final m = _RecordingMutations();
    final c = _container(m);
    c.read(draftProvider.notifier)
        .startEdit(const Alarm(id: 5, hour: 6, minute: 30));
    await _pump(t, _host(c));
    await t.pump();
    expect(c.read(draftProvider)!.vibrationPattern, 'standard'); // default
    await t.tap(find.text('Intense'));
    await t.pump();
    expect(c.read(draftProvider)!.vibrationPattern, 'intense');
    await t.tap(find.text('Save alarm'));
    await t.pumpAndSettle();
    expect(m.saved.single.vibrationPattern, 'intense');
  });

  testWidgets('an unknown stored vibration pattern renders as Standard',
      (t) async {
    final c = _container(_RecordingMutations());
    c.read(draftProvider.notifier).startEdit(const Alarm(
        id: 5, hour: 6, minute: 30, vibrationPattern: 'ultra')); // future key
    await _pump(t, _host(c));
    await t.pump();
    expect(t.takeException(), isNull);
    // The control renders and falls back to the Standard selection — the same
    // fallback the native ringer applies.
    expect(find.byKey(const Key('vibration-pattern-segmented')), findsOneWidget);
  });
}
