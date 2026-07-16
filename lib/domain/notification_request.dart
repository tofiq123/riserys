/// One scheduled local notification in an alarm's ring "burst".
///
/// The iOS 16–25 fallback simulates a ringing alarm by scheduling several
/// notifications 30 s apart, each with a ≤30 s sound. [burstIndex] 0 is the
/// alarm's first notification; later indices are the follow-ups that keep the
/// sound going. [fireAtEpochMs] is absolute UTC — all wall-clock/DST reasoning
/// already happened upstream in ScheduleMath.
class NotificationRequest {
  const NotificationRequest({
    required this.alarmId,
    required this.fireAtEpochMs,
    required this.label,
    required this.sound,
    required this.burstIndex,
    required this.burstTotal,
  });

  final int alarmId;
  final int fireAtEpochMs;
  final String label;
  final String sound;
  final int burstIndex;
  final int burstTotal;

  bool get isPrimary => burstIndex == 0;

  @override
  bool operator ==(Object other) =>
      other is NotificationRequest &&
      other.alarmId == alarmId &&
      other.fireAtEpochMs == fireAtEpochMs &&
      other.label == label &&
      other.sound == sound &&
      other.burstIndex == burstIndex &&
      other.burstTotal == burstTotal;

  @override
  int get hashCode =>
      Object.hash(alarmId, fireAtEpochMs, label, sound, burstIndex, burstTotal);

  @override
  String toString() =>
      'NotificationRequest(alarm: $alarmId, at: $fireAtEpochMs, $burstIndex/$burstTotal)';
}
