import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/account_backup.dart';
import '../../domain/alarm.dart';
import '../../domain/wake_event.dart';
import 'backup_service.dart';

/// Production [BackupService]: the account's alarms + wake history as a single
/// JSON blob in `public.account_backups` (one row per user, RLS in migration
/// 0008). Only constructed when configured, and only off the alarm path.
///
/// Both methods are defensive: `push` swallows every error (a failed backup must
/// never block a mutation or the alarm), and `restore` degrades to "nothing to
/// restore" on any failure. Signed-out is treated as unconfigured — no row to
/// touch.
///
/// NOTE: build-verified only (no live backend in CI). The real flow is exercised
/// by the reinstall-and-restore smoke test in the account-sync setup guide.
class SupabaseBackupService implements BackupService {
  SupabaseBackupService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<void> push(List<Alarm> alarms, List<WakeEvent> wakeEvents) async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return; // signed out — nothing to back up
    try {
      await _client.from('account_backups').upsert({
        'user_id': me,
        'payload': encodeBackup(alarms, wakeEvents),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id');
    } catch (_) {
      // best-effort; a backup failure must never surface to the caller
    }
  }

  @override
  Future<BackupRestoreResult> restore() async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return BackupRestoreResult.none;
    try {
      final row = await _client
          .from('account_backups')
          .select('payload')
          .eq('user_id', me)
          .maybeSingle();
      if (row == null) return BackupRestoreResult.none;
      final payload = row['payload'];
      if (payload is! Map) return BackupRestoreResult.none;
      final decoded = decodeBackup(payload.cast<String, dynamic>());
      return BackupRestoreResult(
        found: true,
        alarms: decoded.alarms,
        wakeEvents: decoded.wakeEvents,
      );
    } catch (_) {
      return BackupRestoreResult.none; // best-effort
    }
  }
}
