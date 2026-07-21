import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/home_departure_checker.dart';
import '../../data/home_location_gateway.dart';
import 'settings_providers.dart';

/// Whether today's wake evidence showed the user clearly beyond their home
/// radius ("up & out"). Set true by the morning departure check after a
/// positive foreground fix (see [homeDepartureCheckerProvider]); reset to false
/// when the next alarm starts ringing (the `WakeRecorder.openRing` hook wired in
/// `wake_providers.dart`).
///
/// DEVICE-LOCAL: this is a single derived boolean. No coordinate, distance, or
/// home anchor ever reaches this layer — only the "left home" verdict — so
/// nothing here can leak a location, whether to the crew status publisher or the
/// on-device wake-evidence card. Lives in this neutral file (not
/// `status_publisher.dart`) so both the publisher and the ring/wake wiring can
/// depend on it without an import cycle.
final leftHomeTodayProvider = StateProvider<bool>((_) => false);

/// The injectable, foreground-only location gateway. Production uses the
/// geolocator-backed implementation; tests override with a fake fix. Never
/// prompts and never throws (see [HomeLocationGateway]).
final homeLocationGatewayProvider = Provider<HomeLocationGateway>(
    (ref) => const GeolocatorHomeLocationGateway());

/// A [HomeDepartureChecker] built from the live gateway + current settings
/// snapshot. Rebuilds when the home anchor or share tier changes. Reads settings
/// via [currentSettingsProvider] so it degrades to "unknown" (never throws)
/// before the store is ready.
final homeDepartureCheckerProvider = Provider<HomeDepartureChecker>(
  (ref) => HomeDepartureChecker(
    gateway: ref.watch(homeLocationGatewayProvider),
    settings: ref.watch(currentSettingsProvider),
  ),
);
