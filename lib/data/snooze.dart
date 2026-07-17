import 'package:flutter/foundation.dart';

import 'alarm_sync_service.dart';
import 'local/wake_event_repository.dart';
import 'native/alarm_api.g.dart';

/// Defers the ringing alarm by [duration] (a snooze). The order mirrors
/// [dismissRingingAlarm]: silence FIRST and unconditionally (a snooze must
/// quiet the alarm immediately), then record + reconcile best-effort. Setting
/// `snoozedUntil` makes the ordinary reconcile arm the alarm for that instant —
/// no parallel scheduler.
///
/// If `stopRinging` throws (the alarm may still be sounding), the throw
/// propagates so the ring screen keeps the screen up rather than falsely
/// reporting the snooze succeeded.
Future<void> snoozeAlarm(int alarmId, Duration duration) async {
  await AlarmHostApi().stopRinging(alarmId);
  try {
    final sync = AlarmSyncService.instance;
    final at = DateTime.now().toUtc().add(duration);
    await sync.repository.setSnoozedUntil(alarmId, at);
    await WakeEventRepository(sync.repository.database).bumpSnooze(alarmId);
    await sync.reconcileNow();
  } catch (e) {
    debugPrint('Rise: could not snooze alarm $alarmId: $e');
  }
}
