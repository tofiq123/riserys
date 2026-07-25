import 'notification_request.dart';
import 'scheduled_occurrence.dart';

/// iOS allows at most this many pending local notifications per app. Every
/// alarm's ring "burst" is drawn from this shared budget, so other notification
/// types (bedtime reminders, wake-up checks — Plan 4) must pass a reduced [cap].
const int kIosNotificationCap = 64;

/// Slots held back from [kIosNotificationCap] for the app's OTHER pending local
/// notifications so they always fit alongside the alarm bursts: the nightly
/// bedtime reminder (1) and post-dismissal wake-checks (a few), plus a little
/// buffer. iOS silently drops requests past the cap, so without this reserve a
/// user with several alarms could crowd those out entirely.
const int kIosReservedHeadroom = 4;

/// The budget the alarm allocator should actually use on iOS — the hard cap
/// minus the reserved [kIosReservedHeadroom]. The allocator's own default stays
/// the hard [kIosNotificationCap] (it is a generic util); the app's iOS fallback
/// (`AlarmSyncService`) passes THIS so alarms never consume the whole cap.
const int kIosAlarmBudget = kIosNotificationCap - kIosReservedHeadroom;

/// Future occurrences, soonest first. Shared by both public functions so the
/// allocation and the drop-count agree exactly.
List<ScheduledOccurrence> _futureSorted(
    List<ScheduledOccurrence> occurrences, DateTime now) {
  final nowMs = now.millisecondsSinceEpoch;
  final future = occurrences
      .where((o) => o.fireAt.millisecondsSinceEpoch > nowMs)
      .toList()
    ..sort((a, b) => a.fireAt.compareTo(b.fireAt));
  return future;
}

/// Per-alarm notification counts, soonest-first, under [cap].
///
/// Rule: give every alarm 1 (a floor, so each fires at least once), as long as
/// there is room; then distribute the remaining budget soonest-first, topping
/// each alarm up toward [perAlarmMax], until the budget is spent. When there
/// are more alarms than the cap, only the soonest [cap] alarms get a slot.
List<int> _counts(List<ScheduledOccurrence> future, int cap, int perAlarmMax) {
  final n = future.length;
  if (n == 0 || cap <= 0) return const [];

  final serviced = n <= cap ? n : cap; // alarms that get at least one slot
  final counts = List<int>.filled(serviced, 1);
  var remaining = cap - serviced;

  for (var i = 0; i < serviced && remaining > 0; i++) {
    final topUp = (perAlarmMax - 1) <= remaining ? (perAlarmMax - 1) : remaining;
    counts[i] += topUp;
    remaining -= topUp;
  }
  return counts;
}

/// The concrete notifications to schedule for the iOS fallback, sorted by fire
/// time, never more than [cap] in total.
List<NotificationRequest> allocateNotifications({
  required List<ScheduledOccurrence> occurrences,
  required DateTime now,
  int cap = kIosNotificationCap,
  int perAlarmMax = 16,
  Duration spacing = const Duration(seconds: 30),
}) {
  final future = _futureSorted(occurrences, now);
  final counts = _counts(future, cap, perAlarmMax);

  final out = <NotificationRequest>[];
  for (var i = 0; i < counts.length; i++) {
    final occ = future[i];
    final total = counts[i];
    final base = occ.fireAt.millisecondsSinceEpoch;
    for (var b = 0; b < total; b++) {
      out.add(NotificationRequest(
        alarmId: occ.alarmId,
        fireAtEpochMs: base + b * spacing.inMilliseconds,
        label: occ.label,
        sound: occ.soundAsset,
        burstIndex: b,
        burstTotal: total,
      ));
    }
  }

  out.sort((a, b) => a.fireAtEpochMs.compareTo(b.fireAtEpochMs));
  return out;
}

/// How many future alarms got zero notifications because the cap was exhausted.
/// Callers log this — the spec forbids silently dropping alarms.
int droppedAlarmCount({
  required List<ScheduledOccurrence> occurrences,
  required DateTime now,
  int cap = kIosNotificationCap,
}) {
  final n = _futureSorted(occurrences, now).length;
  return n > cap ? n - cap : 0;
}
