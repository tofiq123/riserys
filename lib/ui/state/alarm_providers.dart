import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/alarm_sync_service.dart';
import '../../data/local/alarm_repository.dart';
import '../../data/native/alarm_api.g.dart';
import '../../domain/alarm.dart';
import '../../domain/scheduled_occurrence.dart';

/// The app's configured AlarmSyncService. In production this is the singleton
/// built by `AlarmSyncService.configureForApp()` in main(); tests override it
/// with a service over an in-memory database.
final alarmSyncServiceProvider = Provider<AlarmSyncService>((ref) {
  return AlarmSyncService.instance;
});

final alarmRepositoryProvider = Provider<AlarmRepository>((ref) {
  return ref.watch(alarmSyncServiceProvider).repository;
});

/// Live list of the user's alarms from the local database.
final alarmsProvider = StreamProvider<List<Alarm>>((ref) {
  return ref.watch(alarmRepositoryProvider).watchAll();
});

/// Cancels any pending wake-check (notification + re-fire) for [alarmId].
Future<void> defaultCancelWakeCheck(int alarmId) =>
    AlarmHostApi().cancelWakeCheck(alarmId);

/// Every alarm write persists locally AND re-arms the platform scheduler, so
/// the OS never drifts out of sync with the database (the source of truth).
class AlarmMutations {
  AlarmMutations(this._repo, this._sync,
      {this.cancelWakeCheck = defaultCancelWakeCheck});

  final AlarmRepository _repo;
  final AlarmSyncService _sync;

  /// Cancels a pending wake-check when an alarm is deleted or disabled — the
  /// wake-check is armed on dismissal on an entirely separate native
  /// schedule from the one `reconcileNow` manages, so nothing else would
  /// stop it from still sending its "Still up?" notification and re-ring
  /// after the alarm it belongs to is gone. Injectable for tests; defaults
  /// to [defaultCancelWakeCheck].
  final Future<void> Function(int alarmId) cancelWakeCheck;

  Future<void> save(Alarm alarm) async {
    await _repo.upsert(alarm);
    await _sync.reconcileNow();
  }

  Future<void> delete(int id) async {
    await _repo.delete(id);
    await _cancelWakeCheckBestEffort(id);
    await _sync.reconcileNow();
  }

  Future<void> setEnabled(int id, bool enabled) async {
    await _repo.setEnabled(id, enabled);
    if (!enabled) await _cancelWakeCheckBestEffort(id);
    await _sync.reconcileNow();
  }

  /// Best-effort, matching this codebase's treatment of other post-write
  /// native calls (e.g. the ring screen's dismiss/snooze): a failure here
  /// must never block removing or disabling the alarm itself.
  Future<void> _cancelWakeCheckBestEffort(int id) async {
    try {
      await cancelWakeCheck(id);
    } catch (e) {
      debugPrint('Rise: could not cancel wake-check for alarm $id: $e');
    }
  }
}

final alarmMutationsProvider = Provider<AlarmMutations>((ref) {
  return AlarmMutations(ref.watch(alarmRepositoryProvider), ref.watch(alarmSyncServiceProvider));
});

/// The alarm currently being created or edited, or null when no form is open.
class DraftNotifier extends StateNotifier<Alarm?> {
  DraftNotifier() : super(null);

  void startNew() => state =
      const Alarm(id: 0, hour: 6, minute: 30, days: {1, 2, 3, 4, 5});
  void startEdit(Alarm alarm) => state = alarm;
  void update(Alarm alarm) => state = alarm;
  void clear() => state = null;
}

final draftProvider =
    StateNotifierProvider<DraftNotifier, Alarm?>((ref) => DraftNotifier());

/// The soonest upcoming alarm occurrence, or null if no alarm is enabled.
/// Recomputes whenever the alarm list changes.
final nextOccurrenceProvider = FutureProvider<ScheduledOccurrence?>((ref) async {
  ref.watch(alarmsProvider); // rebuild when alarms change
  final plan = await ref.watch(alarmSyncServiceProvider).currentPlan();
  return plan.isEmpty ? null : plan.first;
});
