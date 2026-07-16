import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:rise/data/alarm_sync_service.dart';
import 'package:rise/data/local/alarm_repository.dart';
import 'package:rise/data/local/database.dart';
import 'package:rise/domain/alarm.dart';
import 'package:rise/domain/notification_request.dart';
import 'package:rise/domain/scheduled_occurrence.dart';

/// Records what the service would have sent to the platform.
class FakeAlarmPlatform implements AlarmPlatform {
  FakeAlarmPlatform({this.systemAlarms = true});

  bool systemAlarms;
  final List<List<ScheduledOccurrence>> reconcileCalls = [];
  final List<ScheduledOccurrence> ringNowCalls = [];
  final List<List<NotificationRequest>> notificationCalls = [];

  @override
  Future<void> reconcile(List<ScheduledOccurrence> occurrences) async =>
      reconcileCalls.add(occurrences);

  @override
  Future<void> ringNow(ScheduledOccurrence occurrence) async =>
      ringNowCalls.add(occurrence);

  @override
  Future<bool> supportsSystemAlarms() async => systemAlarms;

  @override
  Future<void> reconcileNotifications(List<NotificationRequest> requests) async =>
      notificationCalls.add(requests);
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

  test('system-alarm platform uses reconcile, not notifications', () async {
    platform = FakeAlarmPlatform(systemAlarms: true);
    AlarmSyncService.configure(AlarmSyncService(
      repository: repo,
      platform: platform,
      location: tz.getLocation('America/New_York'),
    ));
    await repo.upsert(const Alarm(id: 0, hour: 6, minute: 30));
    await AlarmSyncService.instance.reconcileNow();

    expect(platform.reconcileCalls, hasLength(1));
    expect(platform.notificationCalls, isEmpty);
  });

  test('fallback platform uses a notification burst, not reconcile', () async {
    platform = FakeAlarmPlatform(systemAlarms: false);
    AlarmSyncService.configure(AlarmSyncService(
      repository: repo,
      platform: platform,
      location: tz.getLocation('America/New_York'),
    ));
    await repo.upsert(const Alarm(id: 0, hour: 6, minute: 30));
    await AlarmSyncService.instance.reconcileNow();

    expect(platform.notificationCalls, hasLength(1));
    // A single alarm gets a full 16-notification burst.
    expect(platform.notificationCalls.single, hasLength(16));
    expect(platform.reconcileCalls, isEmpty,
        reason: 'the fallback platform must not arm system alarms');
  });

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
    // Several hours ahead of "now" so this can never land inside the 30-minute
    // missed window, regardless of the wall-clock time the suite runs at.
    final now = tz.TZDateTime.now(tz.getLocation('America/New_York'));
    final farFuture = now.add(const Duration(hours: 6));
    await repo.upsert(
        Alarm(id: 0, hour: farFuture.hour, minute: farFuture.minute));
    await AlarmSyncService.instance.reconcileNow(recoverMissed: true);
    expect(platform.ringNowCalls, isEmpty);
  });

  test('recovery rings via ringNow and never through reconcile', () async {
    // A one-shot alarm one minute in the past is "missed": nextOccurrence
    // rolls it to tomorrow, so recovery must come from the dedicated path.
    final now = tz.TZDateTime.now(tz.getLocation('America/New_York'));
    final justPassed = now.subtract(const Duration(minutes: 1));
    final upserted = await repo.upsert(
        Alarm(id: 0, hour: justPassed.hour, minute: justPassed.minute));

    await AlarmSyncService.instance.reconcileNow(recoverMissed: true);

    // Recovery must go through ringNow with the missed alarm...
    expect(platform.ringNowCalls, hasLength(1));
    expect(platform.ringNowCalls.single.alarmId, upserted.id);

    // ...and tomorrow's occurrence is still armed via reconcile — recovery
    // must not clobber the rest of the armed set.
    expect(platform.reconcileCalls.single, hasLength(1));
  });

  test(
      'recovery does not ring an alarm dismissed at or after that occurrence',
      () async {
    // Repeating (non-empty days) so recordDismissed does not also disable
    // the alarm — that would suppress recovery for an unrelated reason
    // (`!alarm.enabled`) and the test would not be exercising the dismissal
    // filter at all.
    final now = tz.TZDateTime.now(tz.getLocation('America/New_York'));
    final justPassed = now.subtract(const Duration(minutes: 1));
    final upserted = await repo.upsert(Alarm(
      id: 0,
      hour: justPassed.hour,
      minute: justPassed.minute,
      days: const {0, 1, 2, 3, 4, 5, 6},
    ));

    // First prove it WOULD ring absent a dismissal, and capture the
    // occurrence's exact fireAt so the dismissal timestamp lines up with it.
    await AlarmSyncService.instance.reconcileNow(recoverMissed: true);
    expect(platform.ringNowCalls, hasLength(1));
    final fireAt = platform.ringNowCalls.single.fireAt;

    await repo.recordDismissed(upserted.id, fireAt);
    platform.ringNowCalls.clear();

    await AlarmSyncService.instance.reconcileNow(recoverMissed: true);
    expect(platform.ringNowCalls, isEmpty);
  });

  test(
      'recovery still rings an alarm dismissed before that occurrence '
      '(an older dismissal must not suppress a newer firing)', () async {
    final now = tz.TZDateTime.now(tz.getLocation('America/New_York'));
    final justPassed = now.subtract(const Duration(minutes: 1));
    final upserted = await repo.upsert(Alarm(
      id: 0,
      hour: justPassed.hour,
      minute: justPassed.minute,
      days: const {0, 1, 2, 3, 4, 5, 6},
    ));

    // Simulate a dismissal of an earlier occurrence (e.g. yesterday's),
    // well before today's firing.
    await repo.recordDismissed(
        upserted.id, now.toUtc().subtract(const Duration(days: 1)));

    await AlarmSyncService.instance.reconcileNow(recoverMissed: true);
    expect(platform.ringNowCalls, hasLength(1));
    expect(platform.ringNowCalls.single.alarmId, upserted.id);
  });

  test('currentPlan reports every enabled alarm sorted by fire time', () async {
    await repo.upsert(const Alarm(id: 0, hour: 9, minute: 0));
    await repo.upsert(const Alarm(id: 0, hour: 6, minute: 30));
    final plan = await AlarmSyncService.instance.currentPlan();
    expect(plan, hasLength(2));
    expect(plan.first.fireAt.isBefore(plan.last.fireAt), isTrue);
  });
}
