/// How the app resolves its colour theme. [system] follows the OS light/dark
/// setting; [light] and [dark] force one. Default is [system].
enum RiseThemeMode { system, light, dark }

/// Immutable snapshot of the user's app-level preferences (snooze budget + the
/// wake-up check). Persisted by `AppSettings`; edited via `settingsProvider`.
class RiseSettings {
  const RiseSettings({
    this.snoozeMaxCount = 3,
    this.snoozeFlatMinutes = 0,
    this.wakeCheckEnabled = true,
    this.wakeCheckDelayMinutes = 5,
    this.wakeIntention = '',
    this.targetWakeHour,
    this.targetWakeMinute,
    this.adaptiveMissions = false,
    this.smartWakeCheck = false,
    this.sunriseWake = false,
    this.realLightPrompt = false,
    this.use24HourTime = false,
    this.themeMode = RiseThemeMode.system,
  });

  /// Max snoozes before the button hides (0 disables snooze).
  final int snoozeMaxCount;

  /// A flat snooze length in minutes, or 0 to use the shrinking schedule.
  final int snoozeFlatMinutes;

  final bool wakeCheckEnabled;

  /// Minutes after dismissal before the "still up?" check.
  final int wakeCheckDelayMinutes;

  /// The user's implementation intention — what they'll do the moment the
  /// alarm rings (e.g. "Put my feet on the floor"). Optional; empty when unset.
  /// Shown on the ring screen as a gentle reminder. Evidence-backed: pairing a
  /// cue with a concrete action markedly improves follow-through.
  final String wakeIntention;

  /// The user's steady target wake time (24-hour), or null when unset. Framed
  /// as a gentle rhythm anchor — a consistent wake time is general wellness, not
  /// a treatment. Feeds the honest wake-pattern insights; never used to silently
  /// reschedule alarms. [targetWakeHour] and [targetWakeMinute] are always set
  /// or cleared together — [hasTargetWake] guards reads.
  final int? targetWakeHour;
  final int? targetWakeMinute;

  /// Whether a steady wake time is set (both components present).
  bool get hasTargetWake => targetWakeHour != null && targetWakeMinute != null;

  /// Opt-in adaptive mission difficulty. When on, a user who breezes through
  /// their mission is nudged one tier harder at ring time (never a lockout —
  /// see [adaptiveDifficulty]). Default off keeps the chosen difficulty exactly.
  final bool adaptiveMissions;

  /// Opt-in "smart" wake-check (Phase 11). When on, after a dismissal Rise
  /// fuses passive signals (sustained motion, app interaction, PVT alertness)
  /// into an awake-confidence score: if it's confident the user got up, the
  /// stay-up check is satisfied without a re-ring; if confidence is low OR
  /// unknown it falls back to the ordinary wake-check re-ring. Default off, so
  /// the wake-check behaves exactly as before unless the user enables it. Only
  /// has effect while [wakeCheckEnabled] is on (it refines that check).
  final bool smartWakeCheck;

  /// Opt-in on-screen "sunrise" wake (Phase 10, Sensory). When on, the ring
  /// screen shows an animated dawn-gradient background and gently ramps device
  /// brightness up while the alarm rings. Purely ambient: a phone screen is far
  /// too dim (~30–110 lux) to biologically wake anyone, so this is a pleasant
  /// brightness boost, never sold as the thing that wakes you (that honesty is
  /// the point of the paired "get real light" prompt). Default off.
  final bool sunriseWake;

  /// Whether the ring screen shows a brief, honest "get real light" prompt
  /// (Phase 10, Sensory). Evidence-backed: a phone screen is biologically too
  /// dim to wake anyone, so — warmly and dismissibly — we nudge the user toward
  /// real, bright light (open a window / turn on a lamp), which genuinely helps
  /// alertness. Default on: it's a gentle, non-nagging one-liner, not a gate.
  final bool realLightPrompt;

  /// Whether times are shown in 24-hour ("digital", e.g. 07:05 / 19:30) form
  /// rather than 12-hour AM/PM. Default off (AM/PM) to preserve existing
  /// behaviour; on for the many locales that don't use AM/PM. Purely a display
  /// preference — [Alarm.hour] is always stored in 24-hour form regardless.
  final bool use24HourTime;

  /// The app's colour theme mode (system / light / dark). Default [system]
  /// follows the OS. The app root resolves this to a concrete brightness and
  /// swaps the [RiseColors] palette accordingly.
  final RiseThemeMode themeMode;

  static const _shrinking = [9, 5, 3, 2, 1];

  /// The duration (minutes) of the [index]-th snooze (0-based): a flat value
  /// if configured, else the shrinking schedule (clamped to its last value).
  int snoozeDurationMinutes(int index) {
    if (snoozeFlatMinutes > 0) return snoozeFlatMinutes;
    return _shrinking[index.clamp(0, _shrinking.length - 1)];
  }

  RiseSettings copyWith({
    int? snoozeMaxCount,
    int? snoozeFlatMinutes,
    bool? wakeCheckEnabled,
    int? wakeCheckDelayMinutes,
    String? wakeIntention,
    int? targetWakeHour,
    int? targetWakeMinute,
    bool? adaptiveMissions,
    bool? smartWakeCheck,
    bool? sunriseWake,
    bool? realLightPrompt,
    bool? use24HourTime,
    RiseThemeMode? themeMode,
    // The `field ?? this.field` idiom cannot express "clear this nullable field
    // back to null" — passing null is indistinguishable from not passing it. A
    // sentinel flag keeps the intent explicit at the call site:
    // `copyWith(clearTargetWake: true)` reads unambiguously.
    bool clearTargetWake = false,
  }) =>
      RiseSettings(
        snoozeMaxCount: snoozeMaxCount ?? this.snoozeMaxCount,
        snoozeFlatMinutes: snoozeFlatMinutes ?? this.snoozeFlatMinutes,
        wakeCheckEnabled: wakeCheckEnabled ?? this.wakeCheckEnabled,
        wakeCheckDelayMinutes:
            wakeCheckDelayMinutes ?? this.wakeCheckDelayMinutes,
        wakeIntention: wakeIntention ?? this.wakeIntention,
        targetWakeHour:
            clearTargetWake ? null : (targetWakeHour ?? this.targetWakeHour),
        targetWakeMinute: clearTargetWake
            ? null
            : (targetWakeMinute ?? this.targetWakeMinute),
        adaptiveMissions: adaptiveMissions ?? this.adaptiveMissions,
        smartWakeCheck: smartWakeCheck ?? this.smartWakeCheck,
        sunriseWake: sunriseWake ?? this.sunriseWake,
        realLightPrompt: realLightPrompt ?? this.realLightPrompt,
        use24HourTime: use24HourTime ?? this.use24HourTime,
        themeMode: themeMode ?? this.themeMode,
      );

  @override
  bool operator ==(Object other) =>
      other is RiseSettings &&
      other.snoozeMaxCount == snoozeMaxCount &&
      other.snoozeFlatMinutes == snoozeFlatMinutes &&
      other.wakeCheckEnabled == wakeCheckEnabled &&
      other.wakeCheckDelayMinutes == wakeCheckDelayMinutes &&
      other.wakeIntention == wakeIntention &&
      other.targetWakeHour == targetWakeHour &&
      other.targetWakeMinute == targetWakeMinute &&
      other.adaptiveMissions == adaptiveMissions &&
      other.smartWakeCheck == smartWakeCheck &&
      other.sunriseWake == sunriseWake &&
      other.realLightPrompt == realLightPrompt &&
      other.use24HourTime == use24HourTime &&
      other.themeMode == themeMode;

  @override
  int get hashCode => Object.hash(
      snoozeMaxCount,
      snoozeFlatMinutes,
      wakeCheckEnabled,
      wakeCheckDelayMinutes,
      wakeIntention,
      targetWakeHour,
      targetWakeMinute,
      adaptiveMissions,
      smartWakeCheck,
      sunriseWake,
      realLightPrompt,
      use24HourTime,
      themeMode);
}
