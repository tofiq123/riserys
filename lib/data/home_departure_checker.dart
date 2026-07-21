import '../domain/home_anchor.dart';
import '../domain/rise_settings.dart';
import 'home_location_gateway.dart';

/// Runs the wake-window "did they leave home?" check: ONE foreground location
/// fix, evaluated by the pure [HomeDeparture] geometry. Constructed at check
/// time from the current gateway + settings snapshot; owns no state.
///
/// PRIVACY INVARIANTS (non-negotiable):
///   * Foreground only — this runs while the app is alive during the
///     wake-check window (WhenInUse). There is no background location path.
///   * It never PROMPTS for permission: permission is requested only from the
///     explicit Settings setup flow. Missing permission here just resolves to
///     null (unknown).
///   * The coordinates compared never leave this method; only the tri-state
///     boolean escapes, feeding the wake-confidence fusion and (crew tier
///     only) the "up & out" status flag.
///
/// Flag lifecycle: on a `true` result the ring-side wiring sets
/// `leftHomeTodayProvider` (lib/ui/status_publisher.dart) so the publisher can
/// upgrade awake → "up & out" for the crew tier; the flag is reset when the
/// NEXT alarm starts ringing via `WakeRecorder.openRing`'s `onRingOpened` hook
/// (wired where `wakeRecorderProvider` is built). On a `false` result the
/// wiring should clear the flag (fresh evidence of being home wins); a `null`
/// leaves it untouched.
class HomeDepartureChecker {
  const HomeDepartureChecker({required this.gateway, required this.settings});

  final HomeLocationGateway gateway;
  final RiseSettings settings;

  /// True — clearly beyond the home radius ("up & out"). False — within it.
  /// Null (unknown) when the feature is off, home is unset, or no usable fix
  /// could be taken (permission missing, services off, timeout, accuracy
  /// worse than 100 m). When the tier is off or home is unset the gateway is
  /// never touched — no location read happens at all. Never throws.
  Future<bool?> leftHome() async {
    if (settings.homeShare == HomeShareTier.off) return null;
    final homeLat = settings.homeLat;
    final homeLng = settings.homeLng;
    if (homeLat == null || homeLng == null) return null;

    final fix = await gateway.currentFix();
    if (fix == null) return null;

    return switch (HomeDeparture.evaluate(
      homeLat: homeLat,
      homeLng: homeLng,
      lat: fix.latitude,
      lng: fix.longitude,
      accuracyMeters: fix.accuracyMeters,
    )) {
      HomeDeparture.leftHome => true,
      HomeDeparture.atHome => false,
      HomeDeparture.unknown => null,
    };
  }
}
