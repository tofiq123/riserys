import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/rise_settings.dart';
import '../domain/wake_event.dart';
import 'state/home_providers.dart';
import 'state/settings_providers.dart';
import 'state/wake_providers.dart';

/// How long after the morning's first ring we keep opportunistically checking
/// for a departure. Outside this window the app stops taking fixes — by then the
/// user is simply living their day and a "left home" reading is no longer
/// meaningful as wake evidence.
const Duration kMorningDepartureWindow = Duration(hours: 6);

/// Minimum spacing between foreground fixes, so repeated app-resumes don't spam
/// the location API.
const Duration kMorningDepartureThrottle = Duration(minutes: 3);

/// Mounted in the app shell. This is the ONLY thing that actually *detects* a
/// departure: foreground-only, it takes a single location fix when the app is
/// resumed during the morning window and updates the day-scoped
/// [leftHomeTodayProvider]. No background location, no timers, no polling — the
/// user opening the app after they've left home is the trigger.
///
/// Privacy: the fix's coordinates never leave [homeDepartureCheckerProvider];
/// only the tri-state "left home?" verdict is stored. The check never prompts
/// for permission (that happens only in the explicit home-setup flow) — without
/// permission it silently reads "unknown" and changes nothing.
class MorningDepartureHost extends ConsumerStatefulWidget {
  const MorningDepartureHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<MorningDepartureHost> createState() =>
      _MorningDepartureHostState();
}

class _MorningDepartureHostState extends ConsumerState<MorningDepartureHost>
    with WidgetsBindingObserver {
  DateTime? _lastCheck;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_maybeCheck());
  }

  /// Runs the cheap guards first (no location read unless every one passes),
  /// then takes at most one throttled fix and folds the verdict into the flag.
  Future<void> _maybeCheck() async {
    final settings = ref.read(currentSettingsProvider);
    // Feature off or no anchor set → nothing to detect.
    if (settings.homeShare == HomeShareTier.off || !settings.hasHome) return;
    // Already know they're out today — no need to keep spending fixes.
    if (ref.read(leftHomeTodayProvider)) return;

    final now = DateTime.now();
    // Only within the morning window after the most recent ring.
    final lastRing = _mostRecentRing();
    if (lastRing == null || now.difference(lastRing) > kMorningDepartureWindow) {
      return;
    }
    // Throttle repeated resumes.
    final last = _lastCheck;
    if (last != null && now.difference(last) < kMorningDepartureThrottle) return;
    _lastCheck = now;

    // Self-guarded and never throws; returns null when off/unset/undeterminable.
    final result = await ref.read(homeDepartureCheckerProvider).leftHome();
    if (!mounted) return;
    // Leaving home is proof they woke — sticky for the rest of the wake day
    // (reset only by the next ring). "Still home" (false) and "unknown" (null)
    // simply leave the flag at its current false value; we only ever flip it on.
    if (result == true) {
      ref.read(leftHomeTodayProvider.notifier).state = true;
    }
  }

  /// The most recent alarm firing, or null if nothing is logged yet.
  DateTime? _mostRecentRing() {
    final events = ref.read(wakeEventsProvider).value ?? const <WakeEvent>[];
    DateTime? latest;
    for (final e in events) {
      if (latest == null || e.firstRingAt.isAfter(latest)) latest = e.firstRingAt;
    }
    return latest;
  }

  @override
  Widget build(BuildContext context) {
    // Re-evaluate whenever the wake log changes — the morning's ring just
    // logged, or events finished loading on a cold start where the user is
    // already out. Cheap: _maybeCheck's guards + throttle make the common case
    // (nothing to do, or checked recently) a no-op, so scheduling it every
    // build is safe. Mirrors StatusPublisherHost's watch-then-post-frame shape.
    ref.watch(wakeEventsProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_maybeCheck());
    });
    return widget.child;
  }
}
