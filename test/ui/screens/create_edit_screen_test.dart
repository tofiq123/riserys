import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/alarm.dart';
import 'package:rise/ui/components/segmented.dart';
import 'package:rise/ui/screens/create_edit_screen.dart';
import 'package:rise/ui/state/alarm_providers.dart';

class _RecordingMutations implements AlarmMutations {
  final List<Alarm> saved = [];
  final List<int> deleted = [];
  @override
  Future<void> save(Alarm alarm) async => saved.add(alarm);
  @override
  Future<void> delete(int id) async => deleted.add(id);
  @override
  Future<void> setEnabled(int id, bool enabled) async {}
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

  testWidgets('difficulty control appears only when a mission is chosen', (t) async {
    final c = _container(_RecordingMutations());
    c.read(draftProvider.notifier).startEdit(
        const Alarm(id: 5, hour: 6, minute: 30, mission: 'none'));
    await _pump(t, _host(c));
    await t.pump();
    expect(find.byType(SegmentedControl<String>), findsNothing);
    await t.tap(find.text('Math'));
    await t.pump();
    expect(find.byType(SegmentedControl<String>), findsOneWidget);
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
}
