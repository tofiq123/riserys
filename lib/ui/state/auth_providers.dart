import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/supabase_config.dart';
import '../../data/auth/auth_service.dart';
import '../../data/auth/supabase_auth_service.dart';
import '../../domain/rise_account.dart';

/// The app's [AuthService]. When the backend is configured this is a real
/// [SupabaseAuthService]; otherwise a [DisabledAuthService] (no account,
/// sign-in hidden). Tests override this with a `FakeAuthService`.
final authServiceProvider = Provider<AuthService>((ref) {
  if (!SupabaseConfig.isConfigured) {
    return const DisabledAuthService();
  }
  final service = SupabaseAuthService();
  ref.onDispose(service.dispose);
  return service;
});

/// The current account, or `null` when signed out. Streamed from
/// [authServiceProvider]. The whole app is usable while this is loading or
/// null — auth is purely additive.
final accountProvider = StreamProvider<RiseAccount?>((ref) {
  return ref.watch(authServiceProvider).account();
});
