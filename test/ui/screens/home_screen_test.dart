import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/alarm.dart';
import 'package:rise/domain/scheduled_occurrence.dart';
import 'package:rise/ui/components/rise_switch.dart';
import 'package:rise/ui/screens/home_screen.dart';
import 'package:rise/ui/state/alarm_providers.dart';
import 'package:rise/domain/streak.dart';
import 'package:rise/ui/state/wake_providers.dart';

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
  VoidCallback? onStreak,
  StreakStats streak = StreakStats.empty,
}) {
  return ProviderScope(
    overrides: [
      alarmsProvider.overrideWith((ref) => Stream.value(alarms)),
      nextOccurrenceProvider.overrideWith((ref) async => null),
      alarmMutationsProvider.overrideWithValue(mutations),
      streakProvider.overrideWithValue(streak),
    ],
    child: MaterialApp(
      home: HomeScreen(
        onNew: onNew ?? () {},
        onEdit: onEdit ?? (_) {},
        onPreview: () {},
        onStreak: onStreak,
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

  testWidgets('hero shows the occurrence time even when its alarm is not in the list', (t) async {
    final occ = ScheduledOccurrence(
      alarmId: 999, // deliberately absent from the alarms list
      fireAt: DateTime.now().toUtc().add(const Duration(hours: 2)),
      label: 'Gym',
      soundAsset: '',
      vibrate: true,
      hour: 14,
      minute: 5,
    );
    await t.pumpWidget(ProviderScope(
      overrides: [
        alarmsProvider.overrideWith((ref) => Stream.value(const <Alarm>[])),
        nextOccurrenceProvider.overrideWith((ref) async => occ),
        alarmMutationsProvider.overrideWithValue(_RecordingMutations()),
        streakProvider.overrideWithValue(StreakStats.empty),
      ],
      child: MaterialApp(
        home: HomeScreen(onNew: () {}, onEdit: (_) {}, onPreview: () {}),
      ),
    ));
    await t.pump(); // resolve the FutureProvider
    await t.pump();
    expect(find.text('2:05'), findsOneWidget); // 14:05 → 2:05 PM
    expect(find.text('PM'), findsOneWidget);
  });

  testWidgets('the streak pill shows the current streak', (t) async {
    await t.pumpWidget(_host(
      alarms: const [],
      mutations: _RecordingMutations(),
      streak: const StreakStats(
          current: 5, best: 7, freezesRemaining: 1, byDay: {}),
    ));
    await t.pump();
    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('the streak pill shows Start when there is no streak', (t) async {
    await t.pumpWidget(
        _host(alarms: const [], mutations: _RecordingMutations()));
    await t.pump();
    expect(find.text('Start'), findsOneWidget);
  });

  testWidgets('tapping the streak pill calls onStreak', (t) async {
    var tapped = false;
    await t.pumpWidget(_host(
      alarms: const [],
      mutations: _RecordingMutations(),
      streak: const StreakStats(
          current: 3, best: 3, freezesRemaining: 0, byDay: {}),
      onStreak: () => tapped = true,
    ));
    await t.pump();
    await t.tap(find.text('3'));
    await t.pump();
    expect(tapped, isTrue);
  });
}
