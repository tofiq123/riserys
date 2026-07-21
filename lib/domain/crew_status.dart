/// A crew member's coarse presence, shown in the Crew tab.
///
/// IMPORTANT: real sleep is NOT tracked. [asleep] is a best-effort presence
/// heuristic derived from alarm/wake activity by [deriveStatus] — it means
/// "has a morning alarm coming and hasn't been up recently", not "is asleep".
///
/// [out] ("Up & out") is awake-and-left-home. It is NEVER produced by
/// [deriveStatus]; the status publisher substitutes it for [awake] only when
/// the user explicitly opted into crew sharing (HomeShareTier.crew) AND
/// today's on-device wake evidence says they left home. Privacy invariant:
/// only this derived boolean is ever shared — no coordinate, distance, or
/// home anchor leaves the device.
enum CrewStatus { asleep, waking, awake, out, unknown }

/// Canonical short label for a status dot/chip. [CrewStatus.unknown] maps to
/// the empty string — callers hide the dot entirely rather than label it.
String crewStatusLabel(CrewStatus s) => switch (s) {
      CrewStatus.waking => 'Waking',
      CrewStatus.awake => 'Awake',
      CrewStatus.out => 'Up & out',
      CrewStatus.asleep => 'Asleep',
      CrewStatus.unknown => '',
    };

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
