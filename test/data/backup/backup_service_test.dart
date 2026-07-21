import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/backup/backup_service.dart';
import 'package:rise/domain/alarm.dart';
import 'package:rise/domain/wake_event.dart';

void main() {
  Alarm alarm(int id) => Alarm(id: id, hour: 6, minute: 30);
  WakeEvent event(int id) => WakeEvent(
        id: id,
        alarmId: 1,
        scheduledAt: DateTime.utc(2026, 7, 18, 6),
        firstRingAt: DateTime.utc(2026, 7, 18, 6),
      );

  group('BackupRestoreResult', () {
    test('none is not found and is empty', () {
      expect(BackupRestoreResult.none.found, isFalse);
      expect(BackupRestoreResult.none.isEmpty, isTrue);
    });

    test('a found result with data is not empty', () {
      final r = BackupRestoreResult(found: true, alarms: [alarm(1)]);
      expect(r.found, isTrue);
      expect(r.isEmpty, isFalse);
    });

    test('a found-but-empty backup is distinguishable from none', () {
      const r = BackupRestoreResult(found: true);
      expect(r.found, isTrue);
      expect(r.isEmpty, isTrue);
    });
  });

  group('FakeBackupService', () {
    test('push records count + last payload (defensive copies)', () async {
      final svc = FakeBackupService();
      final alarms = [alarm(1)];
      await svc.push(alarms, [event(1)]);
      expect(svc.pushCount, 1);
      expect(svc.lastPushedAlarms, hasLength(1));
      // mutating the caller's list does not change what was recorded
      alarms.add(alarm(2));
      expect(svc.lastPushedAlarms, hasLength(1));
    });

    test('restore returns the seeded result and counts calls', () async {
      final svc = FakeBackupService(
          stored: BackupRestoreResult(found: true, alarms: [alarm(9)]));
      final r = await svc.restore();
      expect(svc.restoreCount, 1);
      expect(r.found, isTrue);
      expect(r.alarms.single.hour, 6);
    });

    test('setStored swaps the restore result', () async {
      final svc = FakeBackupService();
      expect((await svc.restore()).found, isFalse);
      svc.setStored(const BackupRestoreResult(found: true));
      expect((await svc.restore()).found, isTrue);
    });
  });

  group('DisabledBackupService', () {
    test('push is a silent no-op and restore finds nothing', () async {
      const svc = DisabledBackupService();
      await expectLater(svc.push([alarm(1)], [event(1)]), completes);
      final r = await svc.restore();
      expect(r.found, isFalse);
    });
  });
}
