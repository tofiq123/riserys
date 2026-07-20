/// RevenueCat credentials, supplied at build time via --dart-define. When the
/// API key is missing, RevenueCat is never initialised and the app grants
/// premium to everyone (graceful-degrade to UNLOCKED) — so the app builds and
/// runs with no monetization config at all, exactly as before this phase.
///
/// Mirrors [SupabaseConfig]: gating is on the *service being enabled*, never on
/// compile-time config sprinkled through the app.
class RevenueCatConfig {
  static const apiKey = String.fromEnvironment('REVENUECAT_API_KEY');

  /// The entitlement identifier configured in the RevenueCat dashboard that
  /// grants "Rise Premium". Defaults to `premium`; override per-build if needed.
  static const entitlementId = String.fromEnvironment(
    'REVENUECAT_ENTITLEMENT_ID',
    defaultValue: 'premium',
  );

  static bool get isConfigured => configured(apiKey);

  static bool configured(String apiKey) => apiKey.isNotEmpty;
}
