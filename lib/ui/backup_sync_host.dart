import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/alarm_sync_service.dart';
import '../data/auth/auth_service.dart';
import '../data/backup/backup_coordinator.dart';
import '../data/backup/backup_service.dart';
import '../data/local/alarm_repository.dart';
import '../data/local/wake_event_repository.dart';
import '../domain/alarm.dart';
import '../domain/wake_event.dart';
import 'state/alarm_providers.dart';
import 'state/auth_providers.dart';
import 'state/backup_providers.dart';
import 'state/wake_providers.dart';

/// Writes a fetched cloud backup into local Drift: inserts the alarms (each
/// carries `id == 0`, so they get fresh local ids) and the wake events verbatim,
/// then reconciles so the restored alarms arm natively. Runtime fields
/// (lastDismissedAt / snoozedUntil) are intentionally left unset — they never
/// left the origin device.
///
/// Takes explicit dependencies (not a `Ref`) so both the auto-restore host and
/// the manual Settings restore can share it, and so it is directly unit-testable
/// over an in-memory database.
Future<void> writeRestoreToLocal({
  required AlarmRepository alarmRepo,
  required WakeEventRepository wakeRepo,
  required AlarmSyncService sync,
  required BackupRestoreResult result,
}) async {
  for (final a in result.alarms) {
    await alarmRepo.upsert(a); // id == 0 → insert fresh
  }
  for (final e in result.wakeEvents) {
    await wakeRepo.insertRestored(e);
  }
  await sync.reconcileNow();
}

/// Mounted in the app shell. Two responsibilities, both fully inert when signed
/// out or when auth is unconfigured (no behavior change when off):
///
///  * Auto-restore: once per sign-in, if this device has NO local alarms (fresh
///    install / post-wipe), pull the cloud backup and write it locally.
///  * Auto-push: whenever local alarms / wake events change while signed in,
///    schedule a debounced backup.
///
/// Pushes are held until the initial restore for a sign-in has settled, so a
/// fresh device never backs up its (empty) state over a good cloud backup before
/// restoring it.
class BackupSyncHost extends ConsumerStatefulWidget {
  const BackupSyncHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<BackupSyncHost> createState() => _BackupSyncHostState();
}

class _BackupSyncHostState extends ConsumerState<BackupSyncHost> {
  /// One restore attempt per sign-in.
  bool _restoreAttempted = false;

  /// Gates auto-push until that attempt has settled (prevents an empty-state
  /// push racing ahead of the restore fetch).
  bool _restoreSettled = false;

  /// Last pushed data signature — only reschedule a push when data changed, so
  /// unrelated rebuilds don't keep resetting the debounce window.
  int? _lastPushSig;

  /// Captured during build so [dispose] can cancel a pending push WITHOUT
  /// touching `ref` (which is illegal after the element is disposed).
  BackupCoordinator? _coordinator;

  bool get _enabled => ref.read(authServiceProvider) is! DisabledAuthService;

  @override
  void dispose() {
    _coordinator?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _coordinator = ref.read(backupCoordinatorProvider);

    // Reset the per-sign-in guards (and drop any pending push) on sign-out.
    ref.listen(accountProvider, (_, next) {
      if (next.value == null) {
        _restoreAttempted = false;
        _restoreSettled = false;
        _lastPushSig = null;
        ref.read(backupCoordinatorProvider).cancel();
      }
    });

    final signedIn = ref.watch(accountProvider).value != null;

    if (_enabled && signedIn) {
      if (!_restoreAttempted) {
        _restoreAttempted = true;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          await _maybeRestore();
          if (mounted) setState(() => _restoreSettled = true);
        });
      }

      if (_restoreSettled) {
        _maybeSchedulePush();
      }
    }

    return widget.child;
  }

  /// Schedules a debounced push, but only when the local data actually changed
  /// since the last schedule.
  void _maybeSchedulePush() {
    final alarms = ref.watch(alarmsProvider).value;
    final events = ref.watch(wakeEventsProvider).value;
    if (alarms == null || events == null) return;
    final sig = Object.hash(Object.hashAll(alarms), Object.hashAll(events));
    if (sig == _lastPushSig) return;
    _lastPushSig = sig;
    ref
        .read(backupCoordinatorProvider)
        .schedulePush(signedIn: true, readLocal: _readLocal);
  }

  Future<({List<Alarm> alarms, List<WakeEvent> wakeEvents})>
      _readLocal() async {
    final alarms = await ref.read(alarmRepositoryProvider).all();
    final events = await ref.read(wakeEventRepositoryProvider).all();
    return (alarms: alarms, wakeEvents: events);
  }

  /// Auto-restore is silent (the alarms just reappear) — no toast.
  Future<void> _maybeRestore() async {
    try {
      final localEmpty =
          (await ref.read(alarmRepositoryProvider).all()).isEmpty;
      await ref.read(backupCoordinatorProvider).restore(
            localAlarmsEmpty: localEmpty,
            apply: (r) => writeRestoreToLocal(
              alarmRepo: ref.read(alarmRepositoryProvider),
              wakeRepo: ref.read(wakeEventRepositoryProvider),
              sync: ref.read(alarmSyncServiceProvider),
              result: r,
            ),
          );
    } catch (_) {
      // Restore is best-effort; never block the app on it.
    }
  }
}
