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
  @override
  Future<void> reconcile(List<ScheduledOccurrence> o) async {}
  @override
  Future<void> ringNow(ScheduledOccurrence o) async {}
  @override
  Future<bool> supportsSystemAlarms() async => true;
  @override
  Future<void> reconcileNotifications(List requests) async {}
}

void main() {
  setUpAll(() => tzdata.initializeTimeZones());

  ProviderContainer makeContainer() {
    final db = RiseDatabase(NativeDatabase.memory());
    final service = AlarmSyncService(
      repository: AlarmRepository(db),
      platform: _FakePlatform(),
      location: tz.getLocation('America/New_York'),
    );
    addTearDown(db.close);
    return ProviderContainer(overrides: [
      alarmSyncServiceProvider.overrideWithValue(service),
    ]);
  }

  test('alarmsProvider streams alarms saved through the mutations', () async {
    final c = makeContainer();
    addTearDown(c.dispose);

    // Prime the stream.
    final sub = c.listen(alarmsProvider, (_, __) {});
    addTearDown(sub.close);

    await c.read(alarmMutationsProvider).save(
        const Alarm(id: 0, hour: 6, minute: 30, label: 'Run'));

    // The StreamProvider re-emits with the new alarm.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final alarms = c.read(alarmsProvider).value ?? const [];
    expect(alarms, hasLength(1));
    expect(alarms.single.label, 'Run');
  });

  test('draftProvider starts, edits, and clears', () {
    final c = makeContainer();
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
