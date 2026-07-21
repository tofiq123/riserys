import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/backup/backup_coordinator.dart';
import 'package:rise/data/backup/backup_service.dart';
import 'package:rise/domain/alarm.dart';
import 'package:rise/domain/wake_event.dart';

/// A hand-driven Timer: never fires on its own. [_ManualScheduler.fireAll] fires
/// every still-active one, so the debounce is exercised without real time.
class _FakeTimer implements Timer {
  bool active = true;
  @override
  bool get isActive => active;
  @override
  void cancel() => active = false;
  @override
  int get tick => 0;
}

class _ManualScheduler {
  final List<({_FakeTimer timer, void Function() cb})> _entries = [];
  int madeCount = 0;

  Timer make(Duration _, void Function() cb) {
    madeCount++;
    final t = _FakeTimer();
    _entries.add((timer: t, cb: cb));
    return t;
  }

  int get liveCount => _entries.where((e) => e.timer.isActive).length;

  Future<void> fireAll() async {
    for (final e in _entries) {
      if (e.timer.isActive) {
        e.timer.active = false;
        e.cb();
      }
    }
    // Let the async _pushNow microtask run.
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  Alarm alarm(int id) => Alarm(id: id, hour: 6, minute: id);
  WakeEvent event(int id) => WakeEvent(
        id: id,
        alarmId: 1,
        scheduledAt: DateTime.utc(2026, 7, 18, 6),
        firstRingAt: DateTime.utc(2026, 7, 18, 6),
      );

  ({List<Alarm> alarms, List<WakeEvent> wakeEvents}) state(int n) =>
      (alarms: [alarm(n)], wakeEvents: [event(n)]);

  group('schedulePush — gating', () {
    test('signed out never schedules or pushes', () async {
      final svc = FakeBackupService();
      final sched = _ManualScheduler();
      final coord =
          BackupCoordinator(svc, timerFactory: sched.make);

      coord.schedulePush(signedIn: false, readLocal: () async => state(1));

      expect(sched.madeCount, 0);
      await sched.fireAll();
      expect(svc.pushCount, 0);
    });

    test('a signed-out call cancels a previously pending push', () async {
      final svc = FakeBackupService();
      final sched = _ManualScheduler();
      final coord = BackupCoordinator(svc, timerFactory: sched.make);

      coord.schedulePush(signedIn: true, readLocal: () async => state(1));
      expect(sched.liveCount, 1);
      coord.schedulePush(signedIn: false, readLocal: () async => state(2));
      expect(sched.liveCount, 0); // pending one was cancelled

      await sched.fireAll();
      expect(svc.pushCount, 0);
    });
  });

  group('schedulePush — debounce / coalescing', () {
    test('rapid schedules collapse into a single push of the LATEST state',
        () async {
      final svc = FakeBackupService();
      final sched = _ManualScheduler();
      final coord = BackupCoordinator(svc, timerFactory: sched.make);

      coord.schedulePush(signedIn: true, readLocal: () async => state(1));
      coord.schedulePush(signedIn: true, readLocal: () async => state(2));
      coord.schedulePush(signedIn: true, readLocal: () async => state(3));

      expect(sched.madeCount, 3); // three timers created
      expect(sched.liveCount, 1); // but only the latest is still armed

      await sched.fireAll();
      expect(svc.pushCount, 1); // exactly one push
      expect(svc.lastPushedAlarms!.single.minute, 3); // the latest state
    });

    test('cancel() drops a pending push', () async {
      final svc = FakeBackupService();
      final sched = _ManualScheduler();
      final coord = BackupCoordinator(svc, timerFactory: sched.make);

      coord.schedulePush(signedIn: true, readLocal: () async => state(1));
      coord.cancel();
      expect(sched.liveCount, 0);
      await sched.fireAll();
      expect(svc.pushCount, 0);
    });

    test('a failing readLocal is swallowed (never throws)', () async {
      final svc = FakeBackupService();
      final sched = _ManualScheduler();
      final coord = BackupCoordinator(svc, timerFactory: sched.make);

      coord.schedulePush(
          signedIn: true,
          readLocal: () async => throw StateError('db down'));
      await sched.fireAll();
      expect(svc.pushCount, 0); // push never reached, but no throw
    });
  });

  group('restore — only-when-empty decision', () {
    test('localNotEmpty short-circuits without touching the backend', () async {
      final svc = FakeBackupService(
          stored: BackupRestoreResult(found: true, alarms: [alarm(1)]));
      final coord = BackupCoordinator(svc);
      var applied = false;

      final outcome = await coord.restore(
        localAlarmsEmpty: false,
        apply: (_) async => applied = true,
      );

      expect(outcome, RestoreOutcome.localNotEmpty);
      expect(applied, isFalse);
      expect(svc.restoreCount, 0); // never even fetched
    });

    test('empty local + no backup row → nothingToRestore', () async {
      final svc = FakeBackupService(); // none
      final coord = BackupCoordinator(svc);
      var applied = false;

      final outcome = await coord.restore(
        localAlarmsEmpty: true,
        apply: (_) async => applied = true,
      );

      expect(outcome, RestoreOutcome.nothingToRestore);
      expect(applied, isFalse);
      expect(svc.restoreCount, 1);
    });

    test('empty local + found-but-empty backup → nothingToRestore', () async {
      final svc = FakeBackupService(
          stored: const BackupRestoreResult(found: true));
      final coord = BackupCoordinator(svc);

      final outcome = await coord.restore(
        localAlarmsEmpty: true,
        apply: (_) async {},
      );
      expect(outcome, RestoreOutcome.nothingToRestore);
    });

    test('empty local + backup with data → restored (apply called)', () async {
      final svc = FakeBackupService(
          stored: BackupRestoreResult(
              found: true, alarms: [alarm(1)], wakeEvents: [event(1)]));
      final coord = BackupCoordinator(svc);
      BackupRestoreResult? appliedWith;

      final outcome = await coord.restore(
        localAlarmsEmpty: true,
        apply: (r) async => appliedWith = r,
      );

      expect(outcome, RestoreOutcome.restored);
      expect(appliedWith, isNotNull);
      expect(appliedWith!.alarms, hasLength(1));
      expect(appliedWith!.wakeEvents, hasLength(1));
    });

    test('a failing apply is contained (reports nothingToRestore, no throw)',
        () async {
      final svc = FakeBackupService(
          stored: BackupRestoreResult(found: true, alarms: [alarm(1)]));
      final coord = BackupCoordinator(svc);

      final outcome = await coord.restore(
        localAlarmsEmpty: true,
        apply: (_) async => throw StateError('write failed'),
      );
      expect(outcome, RestoreOutcome.nothingToRestore);
    });
  });
}
