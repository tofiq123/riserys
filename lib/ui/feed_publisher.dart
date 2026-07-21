import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/wake_event.dart';
import '../data/feed/feed_service.dart';
import 'state/auth_providers.dart';
import 'state/feed_providers.dart';
import 'state/wake_providers.dart';

/// Posts one crew-feed item per finalized on-time wake, de-duplicated so a wake
/// is never posted twice. Dedupe is two-layered: this in-memory guard skips a
/// wake already handled this session (so rebuilds don't re-post), and the
/// server's `unique(user_id, woke_at)` constraint absorbs a re-post across cold
/// starts (see 0009 / [FeedService.publishWake]).
class FeedPublisher {
  FeedPublisher(this._service);

  final FeedService _service;
  int? _lastEventId;

  /// Posts [event] (its dismissal instant, on-time flag, and [streak]) unless it
  /// was already handled this session. Best-effort — errors are swallowed by the
  /// service so a publish never disturbs the wake flow.
  Future<void> maybePublish(WakeEvent? event, {required int streak}) async {
    if (event == null || event.dismissedAt == null) return;
    if (event.id == _lastEventId) return;
    _lastEventId = event.id;
    await _service.publishWake(
      wokeAt: event.dismissedAt!.toUtc(),
      onTime: event.onTime,
      streak: streak,
    );
  }
}

final feedPublisherProvider = Provider<FeedPublisher>(
    (ref) => FeedPublisher(ref.watch(feedServiceProvider)));

/// The signed-in user's most recent finalized on-time wake, or null when signed
/// out / no such wake. Recomputes as the wake log changes (the live DB stream
/// drives this, including after a background dismissal is processed). Only
/// on-time wakes are surfaced — the feed celebrates wins and never shames a miss.
final latestOnTimeWakeProvider = Provider<WakeEvent?>((ref) {
  final account = ref.watch(accountProvider).value;
  if (account == null) return null;
  final events = ref.watch(wakeEventsProvider).value ?? const <WakeEvent>[];
  // events are ordered newest-first (by firstRingAt); take the first finalized
  // on-time one.
  for (final e in events) {
    if (e.dismissedAt != null && e.onTime) return e;
  }
  return null;
});

/// Mounted in the app shell: posts the signed-in user's latest on-time wake to
/// the crew feed when it appears/changes. Renders [child].
class FeedPublisherHost extends ConsumerStatefulWidget {
  const FeedPublisherHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<FeedPublisherHost> createState() => _FeedPublisherHostState();
}

class _FeedPublisherHostState extends ConsumerState<FeedPublisherHost> {
  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(accountProvider).value != null;
    if (signedIn) {
      final event = ref.watch(latestOnTimeWakeProvider);
      final streak = ref.watch(streakProvider).current;
      // Publish after the frame — can't during build; maybePublish dedups so
      // repeated rebuilds for the same wake are cheap no-ops.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(
            ref.read(feedPublisherProvider).maybePublish(event, streak: streak));
      });
    }
    return widget.child;
  }
}
