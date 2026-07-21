import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/crew_status.dart';
import '../domain/rise_settings.dart';
import '../domain/wake_event.dart';
import '../data/status/status_service.dart';
import 'state/alarm_providers.dart';
import 'state/auth_providers.dart';
import 'state/home_providers.dart';
import 'state/settings_providers.dart';
import 'state/status_providers.dart';
import 'state/wake_providers.dart';

/// Deduplicates status publishes: only forwards a value that differs from the
/// last one published, so watching the derived status doesn't spam the backend
/// on every rebuild.
class StatusPublisher {
  StatusPublisher(this._service);

  final StatusService _service;
  CrewStatus? _last;

  Future<void> maybePublish(CrewStatus status) async {
    if (status == _last) return;
    _last = status;
    await _service.publish(status);
  }

  /// Re-sends the last published status (e.g. on app resume) to refresh it.
  Future<void> republish() async {
    final last = _last;
    if (last != null) await _service.publish(last);
  }
}

final statusPublisherProvider = Provider<StatusPublisher>(
    (ref) => StatusPublisher(ref.watch(statusServiceProvider)));

/// The signed-in user's own [CrewStatus], derived from local alarm/wake state,
/// or [CrewStatus.unknown] when signed out. Recomputes when alarms/wake events
/// change; purely time-based transitions are picked up on the next change or on
/// app resume (best-effort — status is not real-time-critical).
final derivedStatusProvider = Provider<CrewStatus>((ref) {
  final account = ref.watch(accountProvider).value;
  if (account == null) return CrewStatus.unknown;
  final next = ref.watch(nextOccurrenceProvider).value;
  final events = ref.watch(wakeEventsProvider).value ?? const <WakeEvent>[];
  final hasOpen = events.any((e) => e.isOpen);
  DateTime? lastDismissed;
  for (final e in events) {
    final d = e.dismissedAt;
    if (d != null && (lastDismissed == null || d.isAfter(lastDismissed))) {
      lastDismissed = d;
    }
  }
  final status = deriveStatus(
    now: DateTime.now().toUtc(),
    nextAlarmAt: next?.fireAt.toUtc(),
    hasOpenWakeEvent: hasOpen,
    lastDismissedAt: lastDismissed?.toUtc(),
  );
  // "Up & out": upgrade awake → out ONLY when the user explicitly opted into
  // crew sharing AND today's on-device wake evidence says they left home.
  // Everything consulted here is a derived boolean or a local setting — the
  // home anchor / coordinates never reach this layer, let alone the backend.
  if (status == CrewStatus.awake &&
      ref.watch(currentSettingsProvider).homeShare == HomeShareTier.crew &&
      ref.watch(leftHomeTodayProvider)) {
    return CrewStatus.out;
  }
  return status;
});

/// Mounted in the app shell: publishes the signed-in user's derived status
/// whenever it changes, and republishes on app resume. Renders [child].
class StatusPublisherHost extends ConsumerStatefulWidget {
  const StatusPublisherHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<StatusPublisherHost> createState() =>
      _StatusPublisherHostState();
}

class _StatusPublisherHostState extends ConsumerState<StatusPublisherHost>
    with WidgetsBindingObserver {
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
    // Only republish while signed in — don't refresh a status for a signed-out
    // session (the backend also guards this, but defend it here too).
    if (state == AppLifecycleState.resumed &&
        ref.read(accountProvider).value != null) {
      unawaited(ref.read(statusPublisherProvider).republish());
    }
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(accountProvider).value != null;
    if (signedIn) {
      final status = ref.watch(derivedStatusProvider);
      // Publish after the frame — can't during build; maybePublish dedups so
      // repeated rebuilds with the same status are cheap no-ops.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(ref.read(statusPublisherProvider).maybePublish(status));
      });
    }
    return widget.child;
  }
}
