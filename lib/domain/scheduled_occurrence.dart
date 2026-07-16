import 'package:collection/collection.dart';

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
    this.hour = 0,
    this.minute = 0,
    this.weekdays = const {},
  });

  final int alarmId;
  final DateTime fireAt;
  final String label;
  final String soundAsset;
  final bool vibrate;

  /// Recurrence pattern for platforms that own recurrence (iOS). 0=Sun…6=Sat;
  /// empty = one-shot. Android ignores these and uses [fireAt].
  final int hour;
  final int minute;
  final Set<int> weekdays;

  @override
  bool operator ==(Object other) =>
      other is ScheduledOccurrence &&
      other.alarmId == alarmId &&
      other.fireAt.isAtSameMomentAs(fireAt) &&
      other.label == label &&
      other.soundAsset == soundAsset &&
      other.vibrate == vibrate &&
      other.hour == hour &&
      other.minute == minute &&
      const SetEquality<int>().equals(other.weekdays, weekdays);

  @override
  int get hashCode => Object.hash(alarmId, fireAt.toUtc(), label, soundAsset,
      vibrate, hour, minute, const SetEquality<int>().hash(weekdays));

  @override
  String toString() =>
      'ScheduledOccurrence(alarm: $alarmId, fireAt: ${fireAt.toIso8601String()})';
}
