/// Backend credentials, supplied at build time via --dart-define. When any is
/// missing the app runs fully local (Supabase is never initialised and sign-in
/// is hidden) — so the app builds and runs with no credentials at all.
class SupabaseConfig {
  static const url = String.fromEnvironment('SUPABASE_URL');
  static const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const googleServerClientId =
      String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  static bool get isConfigured => configured(url, anonKey, googleServerClientId);

  static bool configured(String url, String anonKey, String clientId) =>
      url.isNotEmpty && anonKey.isNotEmpty && clientId.isNotEmpty;
}
