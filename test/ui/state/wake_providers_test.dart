import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/local/alarm_repository.dart';
import 'package:rise/data/local/database.dart';
import 'package:rise/domain/alarm.dart';
import 'package:rise/domain/wake_event.dart';
import 'package:rise/ui/state/alarm_providers.dart';
import 'package:rise/ui/state/wake_providers.dart';

void main() {
  test('streakProvider is empty with no events', () async {
    final c = ProviderContainer(overrides: [
      wakeEventsProvider.overrideWith((ref) => Stream.value(const <WakeEvent>[])),
    ]);
    addTearDown(c.dispose);
    await c.read(wakeEventsProvider.future);
    expect(c.read(streakProvider).current, 0);
  });

  test('streakProvider counts an on-time event today as a streak of 1', () async {
    final today = DateTime.now();
    final e = WakeEvent(
      id: 1,
      alarmId: 1,
      scheduledAt: today,
      firstRingAt: today,
      dismissedAt: today.add(const Duration(minutes: 2)),
      onTime: true,
    );
    final c = ProviderContainer(overrides: [
      wakeEventsProvider.overrideWith((ref) => Stream.value([e])),
    ]);
    addTearDown(c.dispose);
    await c.read(wakeEventsProvider.future);
    expect(c.read(streakProvider).current, 1);
  });

  test('the real provider chain records a ring and surfaces it via wakeEventsProvider',
      () async {
    final db = RiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final alarmRepo = AlarmRepository(db);
    final c = ProviderContainer(overrides: [
      alarmRepositoryProvider.overrideWithValue(alarmRepo),
    ]);
    addTearDown(c.dispose);

    final saved = await alarmRepo
        .upsert(const Alarm(id: 0, hour: 6, minute: 30, label: 'Run'));
    // Resolve the REAL wakeRecorderProvider (built from alarmRepositoryProvider),
    // not an override.
    await c.read(wakeRecorderProvider).openRing(saved.id);

    final events = await c.read(wakeEventsProvider.future);
    expect(events, hasLength(1));
    expect(events.single.alarmId, saved.id);
    expect(events.single.label, 'Run');
    expect(events.single.isOpen, isTrue);
  });
}
