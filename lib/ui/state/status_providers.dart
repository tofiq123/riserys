import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/supabase_config.dart';
import '../../data/status/status_service.dart';
import '../../data/status/supabase_status_service.dart';
import '../../domain/crew_status.dart';

/// The app's [StatusService]. Configured → a real [SupabaseStatusService]
/// (Realtime); otherwise a [DisabledStatusService] (empty, publish is a no-op).
/// Tests override this with a `FakeStatusService`.
final statusServiceProvider = Provider<StatusService>((ref) {
  if (!SupabaseConfig.isConfigured) {
    return const DisabledStatusService();
  }
  final service = SupabaseStatusService();
  ref.onDispose(service.dispose);
  return service;
});

/// The signed-in user's crew statuses (`userId -> CrewStatus`), live. Empty
/// while loading, unconfigured, or signed out — the app is usable regardless.
final crewStatusesProvider = StreamProvider<Map<String, CrewStatus>>((ref) {
  return ref.watch(statusServiceProvider).watch();
});
