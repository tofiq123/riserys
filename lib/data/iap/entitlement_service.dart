import 'dart:async';

/// Which billing period an upgrade offer represents. Kept plugin-independent so
/// the paywall and tests never touch `purchases_flutter` types directly.
enum PremiumPlan { monthly, annual, lifetime, other }

/// A single upgrade option, projected from a RevenueCat package into a
/// plugin-free shape. [id] is the opaque package identifier used to purchase;
/// [priceString] is already localized by the store (e.g. "$4.99").
class PremiumOffer {
  const PremiumOffer({
    required this.id,
    required this.plan,
    required this.priceString,
    this.title,
  });

  final String id;
  final PremiumPlan plan;
  final String priceString;
  final String? title;
}

/// The premium-entitlement gate, abstracted so the whole purchase/restore flow
/// is testable without the store. Production is [RevenueCatEntitlementService];
/// tests use [FakeEntitlementService]; when no RevenueCat key is configured the
/// app uses [UnlockedEntitlementService] (everything unlocked).
///
/// GRACEFUL-DEGRADE CONTRACT: with no configured RevenueCat, [currentIsPremium]
/// is `true` and [isPremium] emits `true` — so merging this phase changes
/// nothing in a build without a key. Only a *configured* RevenueCat with no
/// active entitlement reports `false`.
abstract interface class EntitlementService {
  /// Emits the current premium state on listen, then again on every change
  /// (purchase, restore, or a server-side entitlement update).
  Stream<bool> isPremium();

  /// The last known premium state synchronously.
  bool get currentIsPremium;

  /// The available upgrade offers (empty when unconfigured or none are set up).
  Future<List<PremiumOffer>> offers();

  /// Buys [offer]; returns whether premium is now active. Load [offers] first.
  Future<bool> purchase(PremiumOffer offer);

  /// Restores prior purchases; returns whether premium is now active.
  Future<bool> restorePurchases();

  Future<void> dispose();
}

/// Used when no RevenueCat key is configured: EVERYTHING is unlocked. This is
/// the graceful-degrade default that keeps every existing flow and test working
/// unchanged when monetization isn't wired.
class UnlockedEntitlementService implements EntitlementService {
  const UnlockedEntitlementService();

  @override
  bool get currentIsPremium => true;

  @override
  Stream<bool> isPremium() => Stream.value(true);

  @override
  Future<List<PremiumOffer>> offers() async => const [];

  @override
  Future<bool> purchase(PremiumOffer offer) async => true;

  @override
  Future<bool> restorePurchases() async => true;

  @override
  Future<void> dispose() async {}
}

/// In-memory [EntitlementService] for unit/widget tests. Starts at [premium]
/// (default locked), serves the given [offers], and flips premium on purchase.
/// [setPremium] lets a test drive the entitlement stream directly.
class FakeEntitlementService implements EntitlementService {
  FakeEntitlementService({
    bool premium = false,
    List<PremiumOffer> offers = const [],
    this.purchaseSucceeds = true,
  })  : _premium = premium,
        _offers = offers;

  bool _premium;
  final List<PremiumOffer> _offers;

  /// When false, [purchase] leaves premium unchanged and returns false — models
  /// a cancelled or failed store purchase.
  final bool purchaseSucceeds;

  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  @override
  bool get currentIsPremium => _premium;

  @override
  Stream<bool> isPremium() async* {
    yield _premium;
    yield* _controller.stream;
  }

  @override
  Future<List<PremiumOffer>> offers() async => _offers;

  @override
  Future<bool> purchase(PremiumOffer offer) async {
    if (!purchaseSucceeds) return false;
    setPremium(true);
    return true;
  }

  @override
  Future<bool> restorePurchases() async => _premium;

  /// Drives the entitlement stream (e.g. simulate a server-side change).
  void setPremium(bool value) {
    _premium = value;
    _controller.add(value);
  }

  @override
  Future<void> dispose() async => _controller.close();
}
