import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:rise/data/alarm_sync_service.dart';
import 'package:rise/data/local/alarm_repository.dart';
import 'package:rise/data/local/database.dart';
import 'package:rise/domain/alarm.dart';
import 'package:rise/domain/scheduled_occurrence.dart';

/// Records what the service would have sent to the platform.
class FakeAlarmPlatform implements AlarmPlatform {
  final List<List<ScheduledOccurrence>> reconcileCalls = [];
  final List<ScheduledOccurrence> ringNowCalls = [];

  @override
  Future<void> reconcile(List<ScheduledOccurrence> occurrences) async =>
      reconcileCalls.add(occurrences);

  @override
  Future<void> ringNow(ScheduledOccurrence occurrence) async =>
      ringNowCalls.add(occurrence);
}

void main() {
  late RiseDatabase db;
  late AlarmRepository repo;
  late FakeAlarmPlatform platform;

  setUpAll(() => tzdata.initializeTimeZones());

  setUp(() {
    db = RiseDatabase(NativeDatabase.memory());
    repo = AlarmRepository(db);
    platform = FakeAlarmPlatform();
    AlarmSyncService.configure(AlarmSyncService(
      repository: repo,
      platform: platform,
      location: tz.getLocation('America/New_York'),
    ));
  });

  tearDown(() async => db.close());

  test('sends nothing to the platform when there are no alarms', () async {
    await AlarmSyncService.instance.reconcileNow();
    expect(platform.reconcileCalls.single, isEmpty);
  });

  test('sends one enabled alarm to the platform', () async {
    await repo.upsert(const Alarm(id: 0, hour: 6, minute: 30, label: 'Run'));
    await AlarmSyncService.instance.reconcileNow();

    final sent = platform.reconcileCalls.single;
    expect(sent, hasLength(1));
    expect(sent.single.label, 'Run');
    expect(sent.single.fireAt.isUtc, isTrue);
  });

  test('omits disabled alarms', () async {
    await repo.upsert(const Alarm(id: 0, hour: 6, minute: 30, enabled: false));
    await AlarmSyncService.instance.reconcileNow();
    expect(platform.reconcileCalls.single, isEmpty);
  });

  test('reconciling twice with no change sends the same set both times', () async {
    await repo.upsert(const Alarm(id: 0, hour: 6, minute: 30));
    await AlarmSyncService.instance.reconcileNow();
    await AlarmSyncService.instance.reconcileNow();

    expect(platform.reconcileCalls, hasLength(2));
    expect(platform.reconcileCalls[0], equals(platform.reconcileCalls[1]));
  });

  test('does not ring anything when recoverMissed finds no missed alarm', () async {
    await repo.upsert(const Alarm(id: 0, hour: 6, minute: 30));
    await AlarmSyncService.instance.reconcileNow(recoverMissed: true);
    expect(platform.ringNowCalls, isEmpty);
  });

  test('recovery rings via ringNow and never through reconcile', () async {
    // A one-shot alarm one minute in the past is "missed": nextOccurrence
    // rolls it to tomorrow, so recovery must come from the dedicated path.
    final now = tz.TZDateTime.now(tz.getLocation('America/New_York'));
    final justPassed = now.subtract(const Duration(minutes: 1));
    await repo.upsert(
        Alarm(id: 0, hour: justPassed.hour, minute: justPassed.minute));

    await AlarmSyncService.instance.reconcileNow(recoverMissed: true);

    // Tomorrow's occurrence is still armed — recovery must not clobber it.
    expect(platform.reconcileCalls.single, hasLength(1));
  });

  test('currentPlan reports every enabled alarm sorted by fire time', () async {
    await repo.upsert(const Alarm(id: 0, hour: 9, minute: 0));
    await repo.upsert(const Alarm(id: 0, hour: 6, minute: 30));
    final plan = await AlarmSyncService.instance.currentPlan();
    expect(plan, hasLength(2));
    expect(plan.first.fireAt.isBefore(plan.last.fireAt), isTrue);
  });
}
