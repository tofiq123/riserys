import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/alarm_sync_service.dart';
import '../../data/local/alarm_repository.dart';
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

/// Every alarm write persists locally AND re-arms the platform scheduler, so
/// the OS never drifts out of sync with the database (the source of truth).
class AlarmMutations {
  AlarmMutations(this._repo, this._sync);

  final AlarmRepository _repo;
  final AlarmSyncService _sync;

  Future<void> save(Alarm alarm) async {
    await _repo.upsert(alarm);
    await _sync.reconcileNow();
  }

  Future<void> delete(int id) async {
    await _repo.delete(id);
    await _sync.reconcileNow();
  }

  Future<void> setEnabled(int id, bool enabled) async {
    await _repo.setEnabled(id, enabled);
    await _sync.reconcileNow();
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

/// The message shown by the ToastHost, or null when no toast is visible.
final toastProvider = StateProvider<String?>((ref) => null);

/// The soonest upcoming alarm occurrence, or null if no alarm is enabled.
/// Recomputes whenever the alarm list changes.
final nextOccurrenceProvider = FutureProvider<ScheduledOccurrence?>((ref) async {
  ref.watch(alarmsProvider); // rebuild when alarms change
  final plan = await ref.watch(alarmSyncServiceProvider).currentPlan();
  return plan.isEmpty ? null : plan.first;
});
