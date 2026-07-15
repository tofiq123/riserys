import 'package:collection/collection.dart';

/// A user's alarm. Times are stored in 24-hour form; the 12h/AM-PM split is a
/// UI concern only. [days] uses 0=Sunday … 6=Saturday to match the design's
/// S M T W T F S chips; an empty set means the alarm fires once and disables.
class Alarm {
  const Alarm({
    required this.id,
    required this.hour,
    required this.minute,
    this.days = const {},
    this.enabled = true,
    this.label = 'Alarm',
    this.soundAsset = 'sounds/default_alarm.mp3',
    this.vibrate = true,
  })  : assert(hour >= 0 && hour <= 23),
        assert(minute >= 0 && minute <= 59);

  final int id;
  final int hour;
  final int minute;
  final Set<int> days;
  final bool enabled;
  final String label;
  final String soundAsset;
  final bool vibrate;

  bool get isOneShot => days.isEmpty;

  int get hour12 {
    final h = hour % 12;
    return h == 0 ? 12 : h;
  }

  bool get isAm => hour < 12;

  static int to24Hour(int hour12, bool isAm) {
    final h = hour12 % 12;
    return isAm ? h : h + 12;
  }

  Alarm copyWith({
    int? id,
    int? hour,
    int? minute,
    Set<int>? days,
    bool? enabled,
    String? label,
    String? soundAsset,
    bool? vibrate,
  }) {
    return Alarm(
      id: id ?? this.id,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      days: days ?? this.days,
      enabled: enabled ?? this.enabled,
      label: label ?? this.label,
      soundAsset: soundAsset ?? this.soundAsset,
      vibrate: vibrate ?? this.vibrate,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Alarm &&
      other.id == id &&
      other.hour == hour &&
      other.minute == minute &&
      const SetEquality<int>().equals(other.days, days) &&
      other.enabled == enabled &&
      other.label == label &&
      other.soundAsset == soundAsset &&
      other.vibrate == vibrate;

  @override
  int get hashCode => Object.hash(id, hour, minute,
      const SetEquality<int>().hash(days), enabled, label, soundAsset, vibrate);

  @override
  String toString() =>
      'Alarm(id: $id, $hour:${minute.toString().padLeft(2, '0')}, days: $days, enabled: $enabled)';
}
