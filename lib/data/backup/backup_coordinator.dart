import 'dart:async';

import '../../domain/alarm.dart';
import '../../domain/wake_event.dart';
import 'backup_service.dart';

/// What a restore attempt did, so the caller can toast it (or stay silent for an
/// auto-restore).
enum RestoreOutcome {
  /// A backup was found and applied to this (empty) device.
  restored,

  /// Skipped: this device already has alarms. v1 restores ONLY into an empty
  /// device, so an existing local state is never overwritten or merged.
  localNotEmpty,

  /// No backup row, or an empty one — nothing to apply.
  nothingToRestore,
}

/// Reads the current local state to serialize on a push.
typedef ReadLocalState
    = Future<({List<Alarm> alarms, List<WakeEvent> wakeEvents})> Function();

/// Applies a fetched backup to the local database (write alarms + wake events,
/// then reconcile). Supplied by the caller so this class stays free of Drift.
typedef ApplyRestore = Future<void> Function(BackupRestoreResult result);

/// Coordinates the two backup triggers, deliberately free of Flutter/Riverpod so
/// its debounce, gating, and only-when-empty logic are unit-testable without
/// real timers or a database.
///
///  * [schedulePush] debounces auto-backups — rapid calls coalesce into a single
///    push a few seconds after the last one, and it never pushes while signed
///    out (a signed-out call also cancels any pending push).
///  * [restore] fetches the cloud backup and applies it ONLY when the device has
///    no local alarms, reporting a [RestoreOutcome].
///
/// Every path is defensive: a backup/restore failure is swallowed and must never
/// block the app or an alarm.
class BackupCoordinator {
  BackupCoordinator(
    this._service, {
    Duration debounce = const Duration(seconds: 4),
    Timer Function(Duration, void Function())? timerFactory,
  })  : _debounce = debounce,
        _timerFactory = timerFactory ?? Timer.new;

  final BackupService _service;
  final Duration _debounce;
  final Timer Function(Duration, void Function()) _timerFactory;

  Timer? _pending;
  ReadLocalState? _readLatest;

  /// Debounced auto-push. [signedIn] gates it: while signed out this cancels any
  /// pending push and does nothing. [readLocal] is captured so the eventual push
  /// serializes the LATEST local state when the timer fires — several edits in a
  /// burst collapse into one push.
  void schedulePush({
    required bool signedIn,
    required ReadLocalState readLocal,
  }) {
    _pending?.cancel();
    _pending = null;
    if (!signedIn) {
      _readLatest = null;
      return;
    }
    _readLatest = readLocal;
    _pending = _timerFactory(_debounce, () {
      _pending = null;
      final read = _readLatest;
      _readLatest = null;
      if (read != null) unawaited(_pushNow(read));
    });
  }

  Future<void> _pushNow(ReadLocalState read) async {
    try {
      final local = await read();
      await _service.push(local.alarms, local.wakeEvents);
    } catch (_) {
      // best-effort; a backup failure must never propagate
    }
  }

  /// Cancels any pending debounced push (e.g. on host dispose / sign-out).
  void cancel() {
    _pending?.cancel();
    _pending = null;
    _readLatest = null;
  }

  /// Fetches the cloud backup and applies it via [apply] ONLY when
  /// [localAlarmsEmpty]. Returns what happened so the caller can surface it.
  /// Never throws.
  Future<RestoreOutcome> restore({
    required bool localAlarmsEmpty,
    required ApplyRestore apply,
  }) async {
    if (!localAlarmsEmpty) return RestoreOutcome.localNotEmpty;
    final BackupRestoreResult result;
    try {
      result = await _service.restore();
    } catch (_) {
      return RestoreOutcome.nothingToRestore;
    }
    if (!result.found || result.isEmpty) {
      return RestoreOutcome.nothingToRestore;
    }
    try {
      await apply(result);
    } catch (_) {
      // A failed apply must not crash the sign-in / Settings flow.
      return RestoreOutcome.nothingToRestore;
    }
    return RestoreOutcome.restored;
  }
}
