/// A crew member's coarse presence, shown in the Crew tab.
///
/// IMPORTANT: real sleep is NOT tracked. [asleep] is a best-effort presence
/// heuristic derived from alarm/wake activity by [deriveStatus] — it means
/// "has a morning alarm coming and hasn't been up recently", not "is asleep".
enum CrewStatus { asleep, waking, awake, unknown }

/// How recently a dismissal still counts as "up and about".
const _awakeWindow = Duration(hours: 4);

/// How soon an upcoming alarm makes the user "probably still asleep".
const _asleepLookahead = Duration(hours: 10);

/// How long since the last dismissal before "asleep" is plausible again
/// (so a daytime nap doesn't immediately flip you back to asleep).
const _asleepQuietPeriod = Duration(hours: 8);

/// Derives a [CrewStatus] from local alarm/wake signals. Pure and deterministic
/// given [now]. Rules are applied in order; the first match wins.
CrewStatus deriveStatus({
  required DateTime now,
  DateTime? nextAlarmAt,
  required bool hasOpenWakeEvent,
  DateTime? lastDismissedAt,
}) {
  // 1. Mid-wake: an alarm is firing / being dismissed right now.
  if (hasOpenWakeEvent) return CrewStatus.waking;

  // 2. Recently got up (guard against a future timestamp from clock skew).
  if (lastDismissedAt != null &&
      !now.isBefore(lastDismissedAt) &&
      now.difference(lastDismissedAt) <= _awakeWindow) {
    return CrewStatus.awake;
  }

  // 3. A morning alarm is coming soon and they haven't been up recently.
  if (nextAlarmAt != null) {
    final untilAlarm = nextAlarmAt.difference(now);
    final quietLongEnough = lastDismissedAt == null ||
        now.difference(lastDismissedAt) >= _asleepQuietPeriod;
    if (untilAlarm >= Duration.zero &&
        untilAlarm <= _asleepLookahead &&
        quietLongEnough) {
      return CrewStatus.asleep;
    }
  }

  // 4. Nothing conclusive.
  return CrewStatus.unknown;
}
