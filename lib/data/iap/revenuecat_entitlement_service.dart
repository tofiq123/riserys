import 'dart:async';

import 'package:purchases_flutter/purchases_flutter.dart';

import 'entitlement_service.dart';

/// Production [EntitlementService]: RevenueCat (`purchases_flutter`) behind the
/// plugin-free interface. The ONLY file besides main() that imports the plugin,
/// so the rest of the app — and every test — stays plugin-independent.
///
/// NOTE: build-verified only (no store/RevenueCat in CI). The purchase/restore
/// paths are exercised end-to-end by an on-device pass with real store products.
class RevenueCatEntitlementService implements EntitlementService {
  RevenueCatEntitlementService({required this.entitlementId}) {
    _listener = _onCustomerInfo;
    Purchases.addCustomerInfoUpdateListener(_listener);
    // Prime from the current customer info; best-effort — a failure just leaves
    // premium locked until the first entitlement update arrives.
    unawaited(_prime());
  }

  /// One-time global SDK init. Call once at startup (see main()) when a key is
  /// configured. Kept static so main() can init the SDK before any provider
  /// constructs a service instance — mirroring Supabase.initialize().
  static Future<void> configureSdk(String apiKey) =>
      Purchases.configure(PurchasesConfiguration(apiKey));

  final String entitlementId;

  final StreamController<bool> _controller = StreamController<bool>.broadcast();
  late final CustomerInfoUpdateListener _listener;
  bool _current = false;

  /// Packages from the last [offers] call, keyed by identifier, so [purchase]
  /// can resolve the plugin `Package` from a plugin-free [PremiumOffer].
  final Map<String, Package> _packagesById = {};

  Future<void> _prime() async {
    try {
      final info = await Purchases.getCustomerInfo();
      _apply(_isActive(info));
    } catch (_) {
      // best-effort
    }
  }

  void _onCustomerInfo(CustomerInfo info) => _apply(_isActive(info));

  bool _isActive(CustomerInfo info) =>
      info.entitlements.active.containsKey(entitlementId);

  void _apply(bool value) {
    _current = value;
    _controller.add(value);
  }

  @override
  bool get currentIsPremium => _current;

  @override
  Stream<bool> isPremium() async* {
    yield _current;
    yield* _controller.stream;
  }

  @override
  Future<List<PremiumOffer>> offers() async {
    final offerings = await Purchases.getOfferings();
    final current = offerings.current;
    if (current == null) return const [];
    final result = <PremiumOffer>[];
    for (final pkg in current.availablePackages) {
      _packagesById[pkg.identifier] = pkg;
      result.add(PremiumOffer(
        id: pkg.identifier,
        plan: _planOf(pkg.packageType),
        priceString: pkg.storeProduct.priceString,
        title: pkg.storeProduct.title,
      ));
    }
    return result;
  }

  PremiumPlan _planOf(PackageType type) => switch (type) {
        PackageType.monthly => PremiumPlan.monthly,
        PackageType.annual => PremiumPlan.annual,
        PackageType.lifetime => PremiumPlan.lifetime,
        _ => PremiumPlan.other,
      };

  @override
  Future<bool> purchase(PremiumOffer offer) async {
    final package = _packagesById[offer.id];
    if (package == null) {
      throw StateError('Unknown offer "${offer.id}" — call offers() first.');
    }
    final result = await Purchases.purchase(PurchaseParams.package(package));
    final active = _isActive(result.customerInfo);
    _apply(active);
    return active;
  }

  @override
  Future<bool> restorePurchases() async {
    final info = await Purchases.restorePurchases();
    final active = _isActive(info);
    _apply(active);
    return active;
  }

  @override
  Future<void> dispose() async {
    Purchases.removeCustomerInfoUpdateListener(_listener);
    await _controller.close();
  }
}
