/// One concrete future firing of an alarm, handed to the native layer.
///
/// [fireAt] is always UTC: the native side needs an absolute instant, and all
/// wall-clock/DST reasoning has already happened in [nextOccurrence].
class ScheduledOccurrence {
  const ScheduledOccurrence({
    required this.alarmId,
    required this.fireAt,
    required this.label,
    required this.soundAsset,
    required this.vibrate,
  });

  final int alarmId;
  final DateTime fireAt;
  final String label;
  final String soundAsset;
  final bool vibrate;

  @override
  bool operator ==(Object other) =>
      other is ScheduledOccurrence &&
      other.alarmId == alarmId &&
      other.fireAt.isAtSameMomentAs(fireAt) &&
      other.label == label &&
      other.soundAsset == soundAsset &&
      other.vibrate == vibrate;

  @override
  int get hashCode =>
      Object.hash(alarmId, fireAt.toUtc(), label, soundAsset, vibrate);

  @override
  String toString() =>
      'ScheduledOccurrence(alarm: $alarmId, fireAt: ${fireAt.toIso8601String()})';
}
