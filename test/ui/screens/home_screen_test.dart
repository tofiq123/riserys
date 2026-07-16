import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/alarm.dart';
import 'package:rise/ui/components/rise_switch.dart';
import 'package:rise/ui/screens/home_screen.dart';
import 'package:rise/ui/state/alarm_providers.dart';

class _RecordingMutations implements AlarmMutations {
  final List<(int, bool)> enabledCalls = [];
  @override
  Future<void> setEnabled(int id, bool enabled) async => enabledCalls.add((id, enabled));
  @override
  Future<void> save(Alarm alarm) async {}
  @override
  Future<void> delete(int id) async {}
}

Widget _host({
  required List<Alarm> alarms,
  required _RecordingMutations mutations,
  VoidCallback? onNew,
  void Function(Alarm)? onEdit,
}) {
  return ProviderScope(
    overrides: [
      alarmsProvider.overrideWith((ref) => Stream.value(alarms)),
      nextOccurrenceProvider.overrideWith((ref) async => null),
      alarmMutationsProvider.overrideWithValue(mutations),
    ],
    child: MaterialApp(
      home: HomeScreen(
        onNew: onNew ?? () {},
        onEdit: onEdit ?? (_) {},
        onPreview: () {},
      ),
    ),
  );
}

void main() {
  testWidgets('lists an alarm with its time and repeat label', (t) async {
    await t.pumpWidget(_host(
      alarms: const [Alarm(id: 1, hour: 6, minute: 30, label: 'Run', days: {1, 2, 3, 4, 5})],
      mutations: _RecordingMutations(),
    ));
    await t.pump();
    expect(find.text('6:30'), findsOneWidget);
    expect(find.textContaining('Run'), findsOneWidget);
    expect(find.textContaining('Weekdays'), findsOneWidget);
  });

  testWidgets('toggling a row calls setEnabled', (t) async {
    final m = _RecordingMutations();
    await t.pumpWidget(_host(
      alarms: const [Alarm(id: 7, hour: 6, minute: 30, enabled: true)],
      mutations: m,
    ));
    await t.pump();
    await t.tap(find.byType(RiseSwitch).first);
    await t.pump();
    expect(m.enabledCalls, isNotEmpty);
    expect(m.enabledCalls.first, (7, false));
  });

  testWidgets('tapping a row calls onEdit', (t) async {
    Alarm? edited;
    await t.pumpWidget(_host(
      alarms: const [Alarm(id: 3, hour: 7, minute: 0)],
      mutations: _RecordingMutations(),
      onEdit: (a) => edited = a,
    ));
    await t.pump();
    await t.tap(find.text('7:00'));
    await t.pump();
    expect(edited?.id, 3);
  });

  testWidgets('empty state invites the user to add an alarm', (t) async {
    await t.pumpWidget(_host(alarms: const [], mutations: _RecordingMutations()));
    await t.pump();
    expect(find.textContaining('No alarms'), findsOneWidget);
  });
}
