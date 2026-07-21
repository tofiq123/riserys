import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/alarm_sync_service.dart';
import 'package:rise/data/backup/backup_coordinator.dart';
import 'package:rise/data/backup/backup_service.dart';
import 'package:rise/data/local/alarm_repository.dart';
import 'package:rise/data/local/database.dart';
import 'package:rise/data/local/wake_event_repository.dart';
import 'package:rise/domain/alarm.dart';
import 'package:rise/domain/scheduled_occurrence.dart';
import 'package:rise/domain/wake_event.dart';
import 'package:rise/ui/backup_sync_host.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class _FakePlatform implements AlarmPlatform {
  int reconcileCount = 0;
  @override
  Future<void> reconcile(List<ScheduledOccurrence> o) async => reconcileCount++;
  @override
  Future<void> ringNow(ScheduledOccurrence o) async {}
  @override
  Future<bool> supportsSystemAlarms() async => true;
  @override
  Future<void> reconcileNotifications(List<Object?> r) async {}
}

/// The restore WIRING — `BackupCoordinator.restore` + [writeRestoreToLocal] over
/// a real in-memory database. This is the auto-restore + manual-restore code
/// path; the ConsumerState host only decides WHEN to call it (once per sign-in,
/// gated on sign-in), which the coordinator gating tests already cover.
void main() {
  setUpAll(() => tzdata.initializeTimeZones());

  Alarm alarm({int id = 0, int minute = 30}) =>
      Alarm(id: id, hour: 6, minute: minute, label: 'Restored');
  WakeEvent event() => WakeEvent(
        id: 0,
        alarmId: 1,
        scheduledAt: DateTime.utc(2026, 7, 18, 6),
        firstRingAt: DateTime.utc(2026, 7, 18, 6),
        onTime: true,
      );

  late RiseDatabase db;
  late AlarmRepository alarmRepo;
  late WakeEventRepository wakeRepo;
  late _FakePlatform platform;
  late AlarmSyncService service;

  setUp(() {
    db = RiseDatabase(NativeDatabase.memory());
    alarmRepo = AlarmRepository(db);
    wakeRepo = WakeEventRepository(db);
    platform = _FakePlatform();
    service = AlarmSyncService(
      repository: alarmRepo,
      platform: platform,
      location: tz.getLocation('America/New_York'),
    );
  });
  tearDown(() => db.close());

  Future<RestoreOutcome> runRestore(BackupService backup) async {
    final coord = BackupCoordinator(backup);
    return coord.restore(
      localAlarmsEmpty: (await alarmRepo.all()).isEmpty,
      apply: (r) => writeRestoreToLocal(
        alarmRepo: alarmRepo,
        wakeRepo: wakeRepo,
        sync: service,
        result: r,
      ),
    );
  }

  test('restores into an EMPTY device and arms the alarms', () async {
    final backup = FakeBackupService(
        stored: BackupRestoreResult(
            found: true, alarms: [alarm()], wakeEvents: [event()]));

    final before = platform.reconcileCount;
    final outcome = await runRestore(backup);

    expect(outcome, RestoreOutcome.restored);
    final alarms = await alarmRepo.all();
    expect(alarms, hasLength(1));
    expect(alarms.single.label, 'Restored');
    expect(alarms.single.id, greaterThan(0)); // got a fresh local id
    expect(await wakeRepo.all(), hasLength(1));
    expect(platform.reconcileCount, greaterThan(before)); // armed natively
  });

  test('does NOT restore (or fetch) when the device already has alarms',
      () async {
    await alarmRepo.upsert(alarm(minute: 15)); // pre-existing local alarm
    final backup = FakeBackupService(
        stored:
            BackupRestoreResult(found: true, alarms: [alarm(minute: 45)]));

    final outcome = await runRestore(backup);

    expect(outcome, RestoreOutcome.localNotEmpty);
    expect(backup.restoreCount, 0); // short-circuits, never fetches
    final alarms = await alarmRepo.all();
    expect(alarms, hasLength(1));
    expect(alarms.single.minute, 15); // untouched
  });

  test('empty device + no backup restores nothing', () async {
    final outcome = await runRestore(FakeBackupService()); // none
    expect(outcome, RestoreOutcome.nothingToRestore);
    expect(await alarmRepo.all(), isEmpty);
  });

  test('restored alarms carry no runtime fields', () async {
    final backup = FakeBackupService(
        stored: BackupRestoreResult(found: true, alarms: [alarm()]));
    await runRestore(backup);
    final a = (await alarmRepo.all()).single;
    expect(a.lastDismissedAt, isNull);
    expect(a.snoozedUntil, isNull);
  });
}
