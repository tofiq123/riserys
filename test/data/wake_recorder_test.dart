import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/local/alarm_repository.dart';
import 'package:rise/data/local/database.dart';
import 'package:rise/data/local/wake_event_repository.dart';
import 'package:rise/data/wake_recorder.dart';
import 'package:rise/domain/alarm.dart';

void main() {
  late RiseDatabase db;
  late WakeEventRepository events;
  late AlarmRepository alarms;
  late WakeRecorder rec;

  setUp(() {
    db = RiseDatabase(NativeDatabase.memory());
    events = WakeEventRepository(db);
    alarms = AlarmRepository(db);
    rec = WakeRecorder(events, alarms);
  });
  tearDown(() => db.close());

  test('openRing opens an event with the alarm label and today\'s scheduled time',
      () async {
    final saved =
        await alarms.upsert(const Alarm(id: 0, hour: 6, minute: 30, label: 'Run'));
    await rec.openRing(saved.id);
    final all = await events.all();
    expect(all, hasLength(1));
    final e = all.single;
    expect(e.alarmId, saved.id);
    expect(e.label, 'Run');
    expect(e.isOpen, isTrue);
    final s = e.scheduledAt.toLocal();
    expect(s.hour, 6);
    expect(s.minute, 30);
  });

  test('finalizeDismiss closes the open event with the method', () async {
    final saved =
        await alarms.upsert(const Alarm(id: 0, hour: 6, minute: 30, label: 'Run'));
    await rec.openRing(saved.id);
    await rec.finalizeDismiss(saved.id, method: 'mission');
    final e = (await events.all()).single;
    expect(e.isOpen, isFalse);
    expect(e.method, 'mission');
  });

  test('openRing for an unknown alarm falls back to a default label', () async {
    await rec.openRing(999);
    final e = (await events.all()).single;
    expect(e.label, 'Alarm');
    expect(e.alarmId, 999);
  });
}
