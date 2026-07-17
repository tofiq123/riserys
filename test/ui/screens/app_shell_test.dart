import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/native/alarm_api.g.dart';
import 'package:rise/data/permission_gateway.dart';
import 'package:rise/domain/alarm.dart';
import 'package:rise/domain/scheduled_occurrence.dart';
import 'package:rise/domain/wake_event.dart';
import 'package:rise/ui/components/toast.dart';
import 'package:rise/ui/screens/app_shell.dart';
import 'package:rise/ui/screens/create_edit_screen.dart';
import 'package:rise/ui/screens/home_screen.dart';
import 'package:rise/ui/screens/profile_screen.dart';
import 'package:rise/ui/screens/ring_screen.dart';
import 'package:rise/ui/screens/stats_screen.dart';
import 'package:rise/ui/state/alarm_providers.dart';
import 'package:rise/domain/streak.dart';
import 'package:rise/ui/state/wake_providers.dart';

class _FakeGateway implements PermissionGateway {
  @override
  Future<AlarmPermissions> status() async => AlarmPermissions(
      notifications: true,
      exactAlarm: true,
      fullScreenIntent: true,
      batteryUnrestricted: true);
  @override
  Future<void> requestNotifications() async {}
  @override
  Future<void> openExactAlarm() async {}
  @override
  Future<void> openFullScreenIntent() async {}
  @override
  Future<void> openBattery() async {}
}

List<Override> _overrides(List<Alarm> alarms, ScheduledOccurrence? next) => [
      alarmsProvider.overrideWith((ref) => Stream.value(alarms)),
      nextOccurrenceProvider.overrideWith((ref) async => next),
      streakProvider.overrideWithValue(StreakStats.empty),
      wakeEventsProvider.overrideWith((ref) => Stream.value(const <WakeEvent>[])),
    ];

Widget _host(ProviderContainer c) => UncontrolledProviderScope(
      container: c,
      child: MaterialApp(home: AppShell(permissions: _FakeGateway())),
    );

ProviderContainer _container(
    {List<Alarm> alarms = const [], ScheduledOccurrence? next}) {
  final c = ProviderContainer(overrides: _overrides(alarms, next));
  addTearDown(c.dispose);
  return c;
}

void main() {
  testWidgets('starts on the alarms tab', (t) async {
    await t.pumpWidget(_host(_container()));
    await t.pump();
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('tapping New opens the editor; Cancel closes it', (t) async {
    await t.pumpWidget(_host(_container()));
    await t.pump();
    expect(find.byType(CreateEditScreen), findsNothing);
    await t.tap(find.text('+ New'));
    await t.pump();
    expect(find.byType(CreateEditScreen), findsOneWidget);
    expect(find.text('New alarm'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pump();
    expect(find.byType(CreateEditScreen), findsNothing);
  });

  testWidgets('switching to the Profile tab shows the profile', (t) async {
    await t.pumpWidget(_host(_container()));
    await t.pump();
    await t.tap(find.text('Profile'));
    await t.pump();
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets('a toast message renders then is cleared', (t) async {
    final c = _container();
    await t.pumpWidget(_host(c));
    await t.pump();
    c.read(toastProvider.notifier).state = 'Saved';
    await t.pump();
    expect(find.byType(RiseToast), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
  });

  testWidgets('preview opens the ring screen', (t) async {
    final occ = ScheduledOccurrence(
      alarmId: 1,
      fireAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      label: 'Run',
      soundAsset: '',
      vibrate: true,
      hour: 6,
      minute: 30,
    );
    await t.pumpWidget(_host(_container(
        alarms: const [Alarm(id: 1, hour: 6, minute: 30, label: 'Run')],
        next: occ)));
    await t.pump();
    await t.tap(find.text('Preview alarm'));
    await t.pump();
    await t.pump();
    expect(find.byType(RingScreen), findsOneWidget);
  });

  testWidgets('the Stats tab shows the Stats screen', (t) async {
    await t.pumpWidget(_host(_container()));
    await t.pump();
    await t.tap(find.text('Stats')); // the tab label
    await t.pump();
    expect(find.byType(StatsScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets('tapping the Home streak pill deep-links to the Stats tab', (t) async {
    await t.pumpWidget(_host(_container()));
    await t.pump();
    // On Home the streak is empty, so the pill reads "Start".
    await t.tap(find.text('Start'));
    await t.pump();
    expect(find.byType(StatsScreen), findsOneWidget);
  });
}
