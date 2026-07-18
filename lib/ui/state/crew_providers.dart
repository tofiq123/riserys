import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/supabase_config.dart';
import '../../data/crew/crew_service.dart';
import '../../data/crew/supabase_crew_service.dart';
import '../../domain/crew_state.dart';

/// The app's [CrewService]. Configured → a real [SupabaseCrewService];
/// otherwise a [DisabledCrewService] (empty crew, no writes). Tests override
/// this with a `FakeCrewService`.
final crewServiceProvider = Provider<CrewService>((ref) {
  if (!SupabaseConfig.isConfigured) {
    return const DisabledCrewService();
  }
  final service = SupabaseCrewService();
  ref.onDispose(service.dispose);
  return service;
});

/// The signed-in user's live crew (friends / incoming / outgoing). Empty while
/// loading, unconfigured, or signed out — the app is fully usable regardless.
final crewProvider = StreamProvider<CrewState>((ref) {
  return ref.watch(crewServiceProvider).watch();
});
