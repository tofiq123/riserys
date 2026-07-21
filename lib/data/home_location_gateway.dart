import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// One foreground location fix: position + its reported accuracy radius.
class HomeFix {
  const HomeFix({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
  });

  final double latitude;
  final double longitude;

  /// The platform's estimated accuracy radius, meters (68% confidence).
  final double accuracyMeters;
}

/// PRIVACY-CRITICAL, injectable wrapper over the platform location APIs
/// (mirrors the `MotionSensor` gateway pattern: thin, best-effort, all
/// decision logic stays in the pure `HomeDeparture` domain).
///
/// Invariants, non-negotiable:
///   * FOREGROUND ONLY. Fixes are taken while the app is alive/foregrounded
///     during the wake-check window — WhenInUse permission, never background
///     location (no ACCESS_BACKGROUND_LOCATION / NSLocationAlways*).
///   * Coordinates NEVER leave the device. Callers persist the home anchor in
///     local settings only; nothing here (or downstream) syncs a coordinate.
///   * Never throws — every failure (service off, denied, timeout, platform
///     error) resolves to `null` / `false`, which the fusion treats as
///     "unknown", the conservative direction.
abstract interface class HomeLocationGateway {
  /// Requests WhenInUse permission if not yet granted. Returns whether the app
  /// may read location now. Never escalates to background/always. Never throws.
  Future<bool> ensurePermission();

  /// One current fix, or null when permission is missing, location services
  /// are off, the fix times out (~8 s), or the platform errors. Does NOT
  /// prompt for permission — call [ensurePermission] first. Never throws.
  Future<HomeFix?> currentFix();
}

/// Production gateway over the `geolocator` plugin.
class GeolocatorHomeLocationGateway implements HomeLocationGateway {
  const GeolocatorHomeLocationGateway();

  /// How long a single fix may take before we give up and report "unknown".
  static const Duration fixTimeout = Duration(seconds: 8);

  @override
  Future<bool> ensurePermission() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      return permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;
    } catch (_) {
      return false; // platform hiccup → treated as not granted
    }
  }

  @override
  Future<HomeFix?> currentFix() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        return null;
      }
      // timeLimit makes the platform call fail fast; the outer .timeout is a
      // belt-and-braces bound so a misbehaving plugin still resolves.
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: fixTimeout,
        ),
      ).timeout(fixTimeout + const Duration(seconds: 2));
      return HomeFix(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
      );
    } catch (_) {
      return null; // denied/off/timeout/error → unknown, never a throw
    }
  }
}

/// In-memory gateway for tests: canned permission + fix, with call counters.
class FakeHomeLocationGateway implements HomeLocationGateway {
  FakeHomeLocationGateway({this.granted = true, this.fix});

  /// Whether [ensurePermission] reports granted.
  bool granted;

  /// The fix [currentFix] returns (null simulates denied/off/timeout).
  HomeFix? fix;

  int ensurePermissionCalls = 0;
  int currentFixCalls = 0;

  @override
  Future<bool> ensurePermission() async {
    ensurePermissionCalls++;
    return granted;
  }

  @override
  Future<HomeFix?> currentFix() async {
    currentFixCalls++;
    return fix;
  }
}
