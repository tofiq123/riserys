import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/revenuecat_config.dart';
import '../../data/iap/entitlement_service.dart';
import '../../data/iap/revenuecat_entitlement_service.dart';

/// The app's [EntitlementService]. Configured → a real
/// [RevenueCatEntitlementService]; otherwise an [UnlockedEntitlementService]
/// (everything unlocked — the graceful-degrade default). Tests override this
/// with a `FakeEntitlementService`.
final entitlementServiceProvider = Provider<EntitlementService>((ref) {
  if (!RevenueCatConfig.isConfigured) {
    return const UnlockedEntitlementService();
  }
  final service =
      RevenueCatEntitlementService(entitlementId: RevenueCatConfig.entitlementId);
  ref.onDispose(service.dispose);
  return service;
});

/// Whether the user currently has Rise Premium. Streamed from
/// [entitlementServiceProvider]. Unconfigured → always `true` (unlocked).
final isPremiumProvider = StreamProvider<bool>((ref) {
  return ref.watch(entitlementServiceProvider).isPremium();
});

/// The available upgrade offers for the paywall. Empty when unconfigured or no
/// offerings are set up — the paywall then shows placeholder pricing.
final premiumOffersProvider = FutureProvider<List<PremiumOffer>>((ref) {
  return ref.watch(entitlementServiceProvider).offers();
});
