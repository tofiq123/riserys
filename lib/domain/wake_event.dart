/// One logical firing of an alarm: opened when the ring starts, finalised on
/// dismissal. [dismissedAt] == null means still open — and, once the day is
/// past, a miss. All DateTimes are stored UTC; [localDay] does the only
/// local-time reasoning (streak day-grouping).
class WakeEvent {
  const WakeEvent({
    required this.id,
    required this.alarmId,
    required this.scheduledAt,
    required this.firstRingAt,
    this.dismissedAt,
    this.method,
    this.snoozeCount = 0,
    this.missionFailures = 0,
    this.onTime = false,
    this.label = 'Alarm',
  });

  final int id;
  final int alarmId;
  final DateTime scheduledAt;
  final DateTime firstRingAt;
  final DateTime? dismissedAt;

  /// 'mission' | 'slide' | 'safety' | null.
  final String? method;

  final int snoozeCount;
  final int missionFailures;
  final bool onTime;
  final String label;

  bool get isOpen => dismissedAt == null;

  Duration? get timeToWake => dismissedAt?.difference(scheduledAt);

  DateTime get localDay {
    final l = firstRingAt.toLocal();
    return DateTime(l.year, l.month, l.day);
  }

  WakeEvent copyWith({
    int? id,
    int? alarmId,
    DateTime? scheduledAt,
    DateTime? firstRingAt,
    DateTime? dismissedAt,
    String? method,
    int? snoozeCount,
    int? missionFailures,
    bool? onTime,
    String? label,
  }) {
    return WakeEvent(
      id: id ?? this.id,
      alarmId: alarmId ?? this.alarmId,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      firstRingAt: firstRingAt ?? this.firstRingAt,
      dismissedAt: dismissedAt ?? this.dismissedAt,
      method: method ?? this.method,
      snoozeCount: snoozeCount ?? this.snoozeCount,
      missionFailures: missionFailures ?? this.missionFailures,
      onTime: onTime ?? this.onTime,
      label: label ?? this.label,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WakeEvent &&
      other.id == id &&
      other.alarmId == alarmId &&
      other.scheduledAt.isAtSameMomentAs(scheduledAt) &&
      other.firstRingAt.isAtSameMomentAs(firstRingAt) &&
      _sameInstant(other.dismissedAt, dismissedAt) &&
      other.method == method &&
      other.snoozeCount == snoozeCount &&
      other.missionFailures == missionFailures &&
      other.onTime == onTime &&
      other.label == label;

  @override
  int get hashCode => Object.hash(id, alarmId, scheduledAt.toUtc(),
      firstRingAt.toUtc(), dismissedAt?.toUtc(), method, snoozeCount,
      missionFailures, onTime, label);

  @override
  String toString() =>
      'WakeEvent(id: $id, alarm: $alarmId, ring: ${firstRingAt.toIso8601String()}, '
      'dismissed: $dismissedAt, onTime: $onTime, snoozes: $snoozeCount)';
}

bool _sameInstant(DateTime? a, DateTime? b) {
  if (a == null || b == null) return a == null && b == null;
  return a.isAtSameMomentAs(b);
}
