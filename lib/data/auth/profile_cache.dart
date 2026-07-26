import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/rise_account.dart';

/// Last-known signed-in profile, persisted so a relaunch can render the
/// account instantly — no "signed out" flash, no claim-gate flash — while the
/// live `profiles` row is re-fetched in the background. One profile per
/// install: written on every successful profile fetch, cleared on
/// sign-out/delete.
class ProfileCache {
  ProfileCache(this._prefs);

  final SharedPreferences _prefs;

  static const _key = 'cachedProfile';

  /// The cached account, or null when absent, corrupt, or for another user.
  RiseAccount? read(String userId) {
    final raw = _prefs.getString(_key);
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (map['id'] != userId) return null;
      return RiseAccount(
        id: map['id'] as String,
        username: map['username'] as String?,
        displayName: (map['displayName'] as String?) ?? '',
        avatarColor: (map['avatarColor'] as String?) ?? '#7C9CF4',
        email: map['email'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> write(RiseAccount account) => _prefs.setString(
        _key,
        jsonEncode({
          'id': account.id,
          'username': account.username,
          'displayName': account.displayName,
          'avatarColor': account.avatarColor,
          'email': account.email,
        }),
      );

  Future<void> clear() => _prefs.remove(_key);
}
