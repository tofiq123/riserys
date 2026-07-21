import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/supabase_config.dart';
import '../../data/backup/backup_service.dart';
import '../../data/backup/supabase_backup_service.dart';

/// The app's [BackupService]. Configured → a real [SupabaseBackupService];
/// otherwise a [DisabledBackupService] (push no-ops, restore finds nothing).
/// Tests override this with a `FakeBackupService`. Gated exactly like the other
/// social services (crew / groups / leaderboard): the service itself further
/// no-ops when signed out, so this only checks configuration.
final backupServiceProvider = Provider<BackupService>((ref) {
  if (!SupabaseConfig.isConfigured) {
    return const DisabledBackupService();
  }
  return SupabaseBackupService();
});
