import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:rise/data/alarm_sync_service.dart';
import 'package:rise/data/local/alarm_repository.dart';
import 'package:rise/data/local/database.dart';
import 'package:rise/domain/alarm.dart';
import 'package:rise/domain/scheduled_occurrence.dart';
import 'package:rise/ui/state/alarm_providers.dart';

class _FakePlatform implements AlarmPlatform {
  int reconcileCount = 0;

  @override
  Future<void> reconcile(List<ScheduledOccurrence> o) async => reconcileCount++;
  @override
  Future<void> ringNow(ScheduledOccurrence o) async {}
  @override
  Future<bool> supportsSystemAlarms() async => true;
  @override
  Future<void> reconcileNotifications(List requests) async {}
}

void main() {
  setUpAll(() => tzdata.initializeTimeZones());

  ({ProviderContainer container, _FakePlatform platform}) makeContainer() {
    final db = RiseDatabase(NativeDatabase.memory());
    final platform = _FakePlatform();
    final service = AlarmSyncService(
      repository: AlarmRepository(db),
      platform: platform,
      location: tz.getLocation('America/New_York'),
    );
    addTearDown(db.close);
    final container = ProviderContainer(overrides: [
      alarmSyncServiceProvider.overrideWithValue(service),
    ]);
    return (container: container, platform: platform);
  }

  test('alarmsProvider streams alarms saved through the mutations', () async {
    final (:container, :platform) = makeContainer();
    final c = container;
    addTearDown(c.dispose);

    // Prime the stream.
    final sub = c.listen(alarmsProvider, (_, __) {});
    addTearDown(sub.close);

    final reconcileCountBefore = platform.reconcileCount;
    await c.read(alarmMutationsProvider).save(
        const Alarm(id: 0, hour: 6, minute: 30, label: 'Run'));

    // The StreamProvider re-emits with the new alarm.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final alarms = c.read(alarmsProvider).value ?? const [];
    expect(alarms, hasLength(1));
    expect(alarms.single.label, 'Run');

    // Verify reconcile was called after save.
    expect(platform.reconcileCount, greaterThan(reconcileCountBefore));
  });

  test('save then delete reconciles and removes the alarm', () async {
    final (:container, :platform) = makeContainer();
    final c = container;
    addTearDown(c.dispose);

    // Prime the stream.
    final sub = c.listen(alarmsProvider, (_, __) {});
    addTearDown(sub.close);

    // Save an alarm and get its id.
    await c.read(alarmMutationsProvider).save(
        const Alarm(id: 0, hour: 6, minute: 30, label: 'Run'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final savedAlarm = (c.read(alarmsProvider).value ?? const []).single;
    final id = savedAlarm.id;

    final reconcileCountBefore = platform.reconcileCount;
    await c.read(alarmMutationsProvider).delete(id);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // Verify alarm is removed.
    final alarms = c.read(alarmsProvider).value ?? const [];
    expect(alarms, hasLength(0));

    // Verify reconcile was called after delete.
    expect(platform.reconcileCount, greaterThan(reconcileCountBefore));
  });

  test('setEnabled reconciles and toggles the alarm', () async {
    final (:container, :platform) = makeContainer();
    final c = container;
    addTearDown(c.dispose);

    // Prime the stream.
    final sub = c.listen(alarmsProvider, (_, __) {});
    addTearDown(sub.close);

    // Save an alarm and get its id.
    await c.read(alarmMutationsProvider).save(
        const Alarm(id: 0, hour: 6, minute: 30, label: 'Run', enabled: true));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final savedAlarm = (c.read(alarmsProvider).value ?? const []).single;
    final id = savedAlarm.id;

    final reconcileCountBefore = platform.reconcileCount;
    await c.read(alarmMutationsProvider).setEnabled(id, false);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // Verify alarm's enabled status changed.
    final alarms = c.read(alarmsProvider).value ?? const [];
    expect(alarms.single.enabled, false);

    // Verify reconcile was called after setEnabled.
    expect(platform.reconcileCount, greaterThan(reconcileCountBefore));
  });

  test('delete cancels a pending wake-check for that alarm', () async {
    final db = RiseDatabase(NativeDatabase.memory());
    final platform = _FakePlatform();
    final service = AlarmSyncService(
      repository: AlarmRepository(db),
      platform: platform,
      location: tz.getLocation('America/New_York'),
    );
    addTearDown(db.close);
    final cancelled = <int>[];
    final c = ProviderContainer(overrides: [
      alarmSyncServiceProvider.overrideWithValue(service),
      alarmMutationsProvider.overrideWith((ref) => AlarmMutations(
            ref.watch(alarmRepositoryProvider),
            ref.watch(alarmSyncServiceProvider),
            cancelWakeCheck: (id) async => cancelled.add(id),
          )),
    ]);
    addTearDown(c.dispose);

    final sub = c.listen(alarmsProvider, (_, __) {});
    addTearDown(sub.close);

    await c
        .read(alarmMutationsProvider)
        .save(const Alarm(id: 0, hour: 6, minute: 30, label: 'Run'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final id = (c.read(alarmsProvider).value ?? const []).single.id;

    await c.read(alarmMutationsProvider).delete(id);

    expect(cancelled, [id]);
  });

  test(
      'disabling an alarm cancels a pending wake-check; enabling one does not',
      () async {
    final db = RiseDatabase(NativeDatabase.memory());
    final platform = _FakePlatform();
    final service = AlarmSyncService(
      repository: AlarmRepository(db),
      platform: platform,
      location: tz.getLocation('America/New_York'),
    );
    addTearDown(db.close);
    final cancelled = <int>[];
    final c = ProviderContainer(overrides: [
      alarmSyncServiceProvider.overrideWithValue(service),
      alarmMutationsProvider.overrideWith((ref) => AlarmMutations(
            ref.watch(alarmRepositoryProvider),
            ref.watch(alarmSyncServiceProvider),
            cancelWakeCheck: (id) async => cancelled.add(id),
          )),
    ]);
    addTearDown(c.dispose);

    final sub = c.listen(alarmsProvider, (_, __) {});
    addTearDown(sub.close);

    await c.read(alarmMutationsProvider).save(
        const Alarm(id: 0, hour: 6, minute: 30, label: 'Run', enabled: true));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final id = (c.read(alarmsProvider).value ?? const []).single.id;

    await c.read(alarmMutationsProvider).setEnabled(id, false);
    expect(cancelled, [id]);

    await c.read(alarmMutationsProvider).setEnabled(id, true);
    expect(cancelled, [id]); // re-enabling must not cancel anything new
  });

  test('a failing wake-check cancel never blocks delete or setEnabled',
      () async {
    final db = RiseDatabase(NativeDatabase.memory());
    final platform = _FakePlatform();
    final service = AlarmSyncService(
      repository: AlarmRepository(db),
      platform: platform,
      location: tz.getLocation('America/New_York'),
    );
    addTearDown(db.close);
    final c = ProviderContainer(overrides: [
      alarmSyncServiceProvider.overrideWithValue(service),
      alarmMutationsProvider.overrideWith((ref) => AlarmMutations(
            ref.watch(alarmRepositoryProvider),
            ref.watch(alarmSyncServiceProvider),
            cancelWakeCheck: (_) async => throw StateError('channel down'),
          )),
    ]);
    addTearDown(c.dispose);

    final sub = c.listen(alarmsProvider, (_, __) {});
    addTearDown(sub.close);

    await c
        .read(alarmMutationsProvider)
        .save(const Alarm(id: 0, hour: 6, minute: 30, label: 'Run'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final id = (c.read(alarmsProvider).value ?? const []).single.id;

    await c.read(alarmMutationsProvider).setEnabled(id, false);
    await c.read(alarmMutationsProvider).delete(id);

    final alarms = c.read(alarmsProvider).value ?? const [];
    expect(alarms, hasLength(0));
  });

  test('draftProvider starts, edits, and clears', () {
    final (:container, :platform) = makeContainer();
    final c = container;
    addTearDown(c.dispose);
    final notifier = c.read(draftProvider.notifier);

    expect(c.read(draftProvider), isNull);
    notifier.startNew();
    expect(c.read(draftProvider)!.days, {1, 2, 3, 4, 5});
    notifier.update(c.read(draftProvider)!.copyWith(mission: 'math'));
    expect(c.read(draftProvider)!.mission, 'math');
    notifier.clear();
    expect(c.read(draftProvider), isNull);
  });
}
