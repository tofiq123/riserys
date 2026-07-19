import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/supabase_config.dart';
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
      final account = ref.watch(accountProvider).value;
      if (account != null && !_registered) {
        _registered = true;
        final id = account.id;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          unawaited(ref.read(pushRegistrarProvider).register(id));
        });
      } else if (account == null && _registered) {
        _registered = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          unawaited(ref.read(pushRegistrarProvider).unregister());
        });
      }
    }
    return widget.child;
  }
}
