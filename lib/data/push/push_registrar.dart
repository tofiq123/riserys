import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Registers this device's FCM token to `device_tokens` so the server can push
/// nudges. Build-verified only (firebase_messaging is platform-bound). Every
/// method is best-effort — a failure never affects the app.
class PushRegistrar {
  PushRegistrar({SupabaseClient? client, FirebaseMessaging? messaging})
      : _client = client ?? Supabase.instance.client,
        _messaging = messaging ?? FirebaseMessaging.instance;

  final SupabaseClient _client;
  final FirebaseMessaging _messaging;
  StreamSubscription<String>? _refreshSub;
  String? _lastToken;

  /// Requests notification permission, registers the current token for [userId],
  /// and keeps it fresh on refresh. Safe to call repeatedly.
  Future<void> register(String userId) async {
    try {
      await _messaging.requestPermission();
      final token = await _messaging.getToken();
      if (token != null) {
        _lastToken = token;
        await _upsert(userId, token);
      }
      _refreshSub ??= _messaging.onTokenRefresh.listen((t) {
        _lastToken = t;
        unawaited(_upsert(userId, t));
      });
    } catch (_) {
      // best-effort; nudges just won't reach this device
    }
  }

  Future<void> _upsert(String userId, String token) async {
    try {
      await _client.from('device_tokens').upsert({
        'user_id': userId,
        'token': token,
        'platform': 'android',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id,token');
    } catch (_) {}
  }

  /// Removes this device's token (on sign-out). Best-effort.
  Future<void> unregister() async {
    await _refreshSub?.cancel();
    _refreshSub = null;
    final token = _lastToken;
    _lastToken = null;
    if (token == null) return;
    try {
      await _client.from('device_tokens').delete().eq('token', token);
    } catch (_) {}
  }
}

/// Only read when configured + signed in (constructing it touches
/// `Supabase.instance`/`FirebaseMessaging.instance`, which need init).
final pushRegistrarProvider = Provider<PushRegistrar>((ref) => PushRegistrar());
