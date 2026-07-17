/// Immutable snapshot of the user's app-level preferences (snooze budget + the
/// wake-up check). Persisted by `AppSettings`; edited via `settingsProvider`.
class RiseSettings {
  const RiseSettings({
    this.snoozeMaxCount = 3,
    this.snoozeFlatMinutes = 0,
    this.wakeCheckEnabled = true,
    this.wakeCheckDelayMinutes = 5,
  });

  /// Max snoozes before the button hides (0 disables snooze).
  final int snoozeMaxCount;

  /// A flat snooze length in minutes, or 0 to use the shrinking schedule.
  final int snoozeFlatMinutes;

  final bool wakeCheckEnabled;

  /// Minutes after dismissal before the "still up?" check.
  final int wakeCheckDelayMinutes;

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
  }) =>
      RiseSettings(
        snoozeMaxCount: snoozeMaxCount ?? this.snoozeMaxCount,
        snoozeFlatMinutes: snoozeFlatMinutes ?? this.snoozeFlatMinutes,
        wakeCheckEnabled: wakeCheckEnabled ?? this.wakeCheckEnabled,
        wakeCheckDelayMinutes:
            wakeCheckDelayMinutes ?? this.wakeCheckDelayMinutes,
      );

  @override
  bool operator ==(Object other) =>
      other is RiseSettings &&
      other.snoozeMaxCount == snoozeMaxCount &&
      other.snoozeFlatMinutes == snoozeFlatMinutes &&
      other.wakeCheckEnabled == wakeCheckEnabled &&
      other.wakeCheckDelayMinutes == wakeCheckDelayMinutes;

  @override
  int get hashCode => Object.hash(snoozeMaxCount, snoozeFlatMinutes,
      wakeCheckEnabled, wakeCheckDelayMinutes);
}
