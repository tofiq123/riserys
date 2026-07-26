import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/supabase_config.dart';
import '../../data/auth/auth_service.dart';
import '../../data/auth/profile_cache.dart';
import '../../data/auth/supabase_auth_service.dart';
import '../../domain/rise_account.dart';

/// The persisted last-known profile, used to hydrate the signed-in account
/// synchronously at startup. Overridden in main() with a real
/// SharedPreferences-backed cache; null (no cache, skeleton until the live
/// fetch) when preferences failed to load or in bare test scopes.
final profileCacheProvider = Provider<ProfileCache?>((_) => null);

/// The app's [AuthService]. When the backend is configured this is a real
/// [SupabaseAuthService]; otherwise a [DisabledAuthService] (no account,
/// sign-in hidden). Tests override this with a `FakeAuthService`.
final authServiceProvider = Provider<AuthService>((ref) {
  if (!SupabaseConfig.isConfigured) {
    return const DisabledAuthService();
  }
  final service = SupabaseAuthService(cache: ref.watch(profileCacheProvider));
  ref.onDispose(service.dispose);
  return service;
});

/// The current account, or `null` when signed out. Streamed from
/// [authServiceProvider]. The whole app is usable while this is loading or
/// null — auth is purely additive.
final accountProvider = StreamProvider<RiseAccount?>((ref) {
  return ref.watch(authServiceProvider).account();
});
