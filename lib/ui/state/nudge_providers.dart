import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/supabase_config.dart';
import '../../data/nudge/nudge_service.dart';
import '../../data/nudge/supabase_nudge_service.dart';

/// The app's [NudgeService]. Configured → a real [SupabaseNudgeService] (invokes
/// the send-nudge edge function); otherwise a [DisabledNudgeService] (no-op).
/// Tests override this with a `FakeNudgeService`.
final nudgeServiceProvider = Provider<NudgeService>((ref) {
  if (!SupabaseConfig.isConfigured) {
    return const DisabledNudgeService();
  }
  return SupabaseNudgeService();
});
