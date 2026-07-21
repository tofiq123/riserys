/// Pure "left home" geometry for the wake-signal core.
///
/// The user may set a home anchor (lat/lng, stored ONLY on this device). Around
/// wake time — while the app is foregrounded — a single location fix is
/// compared against that anchor: being clearly beyond a radius is a strong
/// "genuinely up and out" signal for the wake-confidence fusion.
///
/// Threshold rationale (documented, deliberately conservative):
///   * Phone GPS is ~5–20 m outdoors and MUCH worse indoors (Wi-Fi/cell fixes
///     can be 30–100+ m). Bed-to-kitchen movement is far below what location
///     can honestly resolve — that is a MOTION signal (pedometer consensus),
///     never a location claim. We never pretend sub-100 m precision.
///   * The departure threshold is `max(120 m, accuracy × 2.5)`: a 120 m floor
///     so a good fix still requires genuinely leaving the property, and an
///     accuracy multiple so a sloppy fix must be proportionally farther out
///     before we claim departure (2.5× keeps the false-positive tail tiny).
///   * A fix with accuracy worse than 100 m is too vague to judge either way —
///     the evaluation returns [HomeDeparture.unknown] and the fusion treats it
///     as no evidence (absence of evidence never counts as being up).
library;

import 'dart:math';

/// Departure threshold floor, meters. Below this distance we never claim the
/// user left home, no matter how good the fix looks.
const double kLeftHomeMinThresholdMeters = 120;

/// Multiplier applied to the fix's reported accuracy: the worse the fix, the
/// farther out the user must be before "left home" is claimed.
const double kLeftHomeAccuracyFactor = 2.5;

/// A fix with accuracy worse than this (meters) is unusable for a home-radius
/// judgment — evaluate returns [HomeDeparture.unknown].
const double kMaxUsableAccuracyMeters = 100;

/// Mean Earth radius (meters) for the haversine distance.
const double _earthRadiusMeters = 6371008.8;

/// Great-circle (haversine) distance in meters between two lat/lng points
/// (degrees). Antimeridian-safe: the formula only uses trig of the deltas, so
/// a longitude wrap (179.99° vs -179.99°) yields the short arc, not the long
/// way round.
double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
  final phi1 = _rad(lat1);
  final phi2 = _rad(lat2);
  final dPhi = _rad(lat2 - lat1);
  final dLambda = _rad(lng2 - lng1);
  final a = pow(sin(dPhi / 2), 2) +
      cos(phi1) * cos(phi2) * pow(sin(dLambda / 2), 2);
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return _earthRadiusMeters * c;
}

double _rad(double deg) => deg * pi / 180;

/// The outcome of comparing a location fix against the home anchor.
enum HomeDeparture {
  /// Clearly beyond the departure threshold — a strong "up and out" signal.
  leftHome,

  /// Within the threshold of home (which, given honest GPS limits, only means
  /// "not demonstrably away" — never "still in bed").
  atHome,

  /// No judgment possible: home unset, or the fix is too imprecise/invalid.
  unknown;

  /// Evaluates one foreground fix ([lat], [lng], [accuracyMeters]) against the
  /// home anchor ([homeLat], [homeLng]).
  ///
  /// Returns [unknown] when the anchor is unset, any coordinate is non-finite,
  /// or the fix accuracy is worse than [kMaxUsableAccuracyMeters]. Otherwise
  /// [leftHome] iff the haversine distance exceeds
  /// `max(kLeftHomeMinThresholdMeters, accuracy × kLeftHomeAccuracyFactor)`,
  /// else [atHome].
  static HomeDeparture evaluate({
    required double? homeLat,
    required double? homeLng,
    required double lat,
    required double lng,
    required double accuracyMeters,
  }) {
    if (homeLat == null || homeLng == null) return unknown;
    if (!homeLat.isFinite ||
        !homeLng.isFinite ||
        !lat.isFinite ||
        !lng.isFinite ||
        !accuracyMeters.isFinite) {
      return unknown;
    }
    if (accuracyMeters > kMaxUsableAccuracyMeters) return unknown;

    final distance = distanceMeters(homeLat, homeLng, lat, lng);
    final threshold = max(
        kLeftHomeMinThresholdMeters, accuracyMeters * kLeftHomeAccuracyFactor);
    return distance > threshold ? leftHome : atHome;
  }
}
