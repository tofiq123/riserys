import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/supabase_config.dart';
import '../data/firebase_ready.dart';
import '../data/push/push_registrar.dart';
import 'state/auth_providers.dart';

/// Registers/unregisters this device's FCM token as the account signs in/out.
/// Gated on [SupabaseConfig.isConfigured] so it NEVER touches Firebase in tests
/// or unconfigured builds. Renders [child].
class PushRegistrarHost extends ConsumerStatefulWidget {
  const PushRegistrarHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PushRegistrarHost> createState() => _PushRegistrarHostState();
}

class _PushRegistrarHostState extends ConsumerState<PushRegistrarHost> {
  bool _registered = false;

  @override
  Widget build(BuildContext context) {
    if (SupabaseConfig.isConfigured) {
      // .valueOrNull, not .value: .value rethrows while accountProvider is in
      // an error state, and this widget wraps the entire app shell below —
      // unlike the Crew-tab-only version of this bug, a throw here would
      // blank the whole app.
      final account = ref.watch(accountProvider).valueOrNull;
      if (account != null && !_registered) {
        _registered = true;
        final id = account.id;
        final registrar = ref.read(pushRegistrarProvider);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          unawaited(_registerAfterFirebaseReady(registrar, id));
        });
      } else if (account == null && _registered) {
        _registered = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          try {
            unawaited(ref.read(pushRegistrarProvider).unregister());
          } catch (e) {
            debugPrint('Rise: could not unregister push token: $e');
          }
        });
      }
    }
    return widget.child;
  }

  /// Waits for the deferred `Firebase.initializeApp()` in main() to settle
  /// before registering — without this, a signed-in account rendering on the
  /// first frame reaches here before Firebase has, and `FirebaseMessaging`
  /// throws `[core/no-app]` (confirmed on-device 2026-08-05). [PushRegistrar]
  /// itself is still best-effort beyond this point.
  Future<void> _registerAfterFirebaseReady(
      PushRegistrar registrar, String id) async {
    try {
      await firebaseReady;
      if (!mounted) return;
      unawaited(registrar.register(id));
    } catch (e) {
      debugPrint('Rise: could not start push registration for $id: $e');
    }
  }
}
