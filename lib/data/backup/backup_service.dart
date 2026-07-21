import '../../domain/alarm.dart';
import '../../domain/wake_event.dart';

/// The outcome of a [BackupService.restore]: whether a cloud backup row was
/// found, and the decoded contents when it was.
///
/// The service only fetches + decodes — it never decides whether to APPLY. The
/// restore-only-when-local-empty policy lives in the coordinator so it stays
/// unit-testable in isolation.
class BackupRestoreResult {
  const BackupRestoreResult({
    required this.found,
    this.alarms = const [],
    this.wakeEvents = const [],
  });

  /// No backup to apply: no row for this account, unconfigured, or signed out.
  static const none = BackupRestoreResult(found: false);

  /// Whether a backup row existed for the account (distinguishes "no backup"
  /// from "a backup that happened to hold nothing").
  final bool found;
  final List<Alarm> alarms;
  final List<WakeEvent> wakeEvents;

  bool get isEmpty => alarms.isEmpty && wakeEvents.isEmpty;
}

/// Per-account cloud backup of local alarms + wake history (see migration 0008
/// and the account-sync spec). Offline-first: the local Drift database stays the
/// source of truth; this is a backup/restore path, not a live authority.
///
/// Production is `SupabaseBackupService`; tests use [FakeBackupService];
/// unconfigured/signed-out uses [DisabledBackupService].
abstract interface class BackupService {
  /// Best-effort: upserts the signed-in user's single backup row with the
  /// current local state. Swallows all errors — a backup failure must NEVER
  /// surface to the UI or block an alarm. No-op when signed out / unconfigured.
  Future<void> push(List<Alarm> alarms, List<WakeEvent> wakeEvents);

  /// Fetches + decodes the signed-in user's backup row, or
  /// [BackupRestoreResult.none] when there is none / unconfigured / signed out.
  /// Never throws.
  Future<BackupRestoreResult> restore();
}

/// In-memory [BackupService] for tests: records pushes and returns a seeded
/// restore result.
class FakeBackupService implements BackupService {
  FakeBackupService({BackupRestoreResult stored = BackupRestoreResult.none})
      : _stored = stored;

  BackupRestoreResult _stored;

  int pushCount = 0;
  List<Alarm>? lastPushedAlarms;
  List<WakeEvent>? lastPushedWakeEvents;
  int restoreCount = 0;

  /// Seed / replace what [restore] returns.
  void setStored(BackupRestoreResult result) => _stored = result;

  @override
  Future<void> push(List<Alarm> alarms, List<WakeEvent> wakeEvents) async {
    pushCount++;
    lastPushedAlarms = List.of(alarms);
    lastPushedWakeEvents = List.of(wakeEvents);
  }

  @override
  Future<BackupRestoreResult> restore() async {
    restoreCount++;
    return _stored;
  }
}

/// Used when unconfigured/signed-out: push is a no-op, restore finds nothing.
/// Never throws.
class DisabledBackupService implements BackupService {
  const DisabledBackupService();

  @override
  Future<void> push(List<Alarm> alarms, List<WakeEvent> wakeEvents) async {}

  @override
  Future<BackupRestoreResult> restore() async => BackupRestoreResult.none;
}
