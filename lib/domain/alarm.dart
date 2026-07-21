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
    this.mission = 'none',
    this.missionDiff = 'easy',
    this.missionCount = 1,
    this.missionData,
    this.lastDismissedAt,
    this.snoozedUntil,
  })  : assert(hour >= 0 && hour <= 23),
        assert(minute >= 0 && minute <= 59),
        assert(missionCount >= 1 && missionCount <= 3);

  final int id;
  final int hour;
  final int minute;
  final Set<int> days;
  final bool enabled;
  final String label;
  final String soundAsset;
  final bool vibrate;

  /// Dismiss mission:
  /// 'none' | 'math' | 'tap' | 'memory' | 'pvt' | 'typing' |
  /// 'shake' | 'qr' | 'steps' | 'photo' | 'eyes'.
  ///
  /// A legacy/unknown key (e.g. the removed 'hold') degrades safely to
  /// slide-to-wake at the mission host, so it never traps the user.
  final String mission;

  /// Mission difficulty: 'easy' | 'medium' | 'hard'.
  final String missionDiff;

  /// How many times the chosen mission must be completed in a row before the
  /// alarm dismisses (a mission "chain"). 1–3; default 1. Only meaningful when
  /// [mission] is not 'none'. Completing the required count always dismisses —
  /// the count never locks the user out.
  final int missionCount;

  /// Mission-specific config, e.g. the registered QR payload the 'qr' mission
  /// must scan, or the reference-photo perceptual hash the 'photo' mission must
  /// match. Null/empty means unconfigured — a mission that reads this must
  /// degrade gracefully (the QR mission accepts any first scan; the photo
  /// mission accepts any photo) so an unconfigured alarm never traps the user.
  /// Ignored by missions that don't need extra config.
  final String? missionData;

  /// UTC instant this alarm was last dismissed, or null if never dismissed.
  /// Recovery uses this to avoid re-ringing an occurrence already dealt with.
  final DateTime? lastDismissedAt;

  /// When set (UTC), the alarm's next firing is this instant instead of its
  /// schedule — a deferred re-ring from a snooze. Cleared on dismissal.
  final DateTime? snoozedUntil;

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
    String? mission,
    String? missionDiff,
    int? missionCount,
    String? missionData,
    DateTime? lastDismissedAt,
    // The `field ?? this.field` idiom used above cannot express "set this
    // nullable field back to null" — passing null is indistinguishable from
    // not passing it at all. That matters here: editing an alarm's time must
    // clear a stale dismissal (an old dismissal must not suppress the newly
    // edited occurrence). A sentinel bool flag is used instead of a sentinel
    // object because it keeps the call site explicit:
    // `copyWith(hour: 7, clearLastDismissedAt: true)` reads unambiguously,
    // whereas a magic "unset" sentinel value would not.
    bool clearLastDismissedAt = false,
    DateTime? snoozedUntil,
    bool clearSnoozedUntil = false,
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
      mission: mission ?? this.mission,
      missionDiff: missionDiff ?? this.missionDiff,
      missionCount: missionCount ?? this.missionCount,
      missionData: missionData ?? this.missionData,
      lastDismissedAt: clearLastDismissedAt
          ? null
          : (lastDismissedAt ?? this.lastDismissedAt),
      snoozedUntil: clearSnoozedUntil
          ? null
          : (snoozedUntil ?? this.snoozedUntil),
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
      other.vibrate == vibrate &&
      other.mission == mission &&
      other.missionDiff == missionDiff &&
      other.missionCount == missionCount &&
      other.missionData == missionData &&
      _sameInstant(other.lastDismissedAt, lastDismissedAt) &&
      _sameInstant(other.snoozedUntil, snoozedUntil);

  @override
  int get hashCode => Object.hash(
      id,
      hour,
      minute,
      const SetEquality<int>().hash(days),
      enabled,
      label,
      soundAsset,
      vibrate,
      mission,
      missionDiff,
      missionCount,
      missionData,
      // Normalized to UTC, not the raw DateTime: Dart's DateTime.== treats a
      // UTC and a local DateTime representing the exact same instant as
      // unequal, even though DateTime.hashCode (derived only from the epoch
      // microsecond value) would already agree for the two. The database
      // round trip hands back a local-flavored DateTime (drift's default
      // unix-seconds storage), while values set in memory are UTC — the
      // .toUtc() here just keeps hashCode consistent with the == above,
      // which does need the normalization to treat the two as equal.
      lastDismissedAt?.toUtc(),
      snoozedUntil?.toUtc());

  @override
  String toString() =>
      'Alarm(id: $id, $hour:${minute.toString().padLeft(2, '0')}, days: $days, '
      'enabled: $enabled, lastDismissedAt: $lastDismissedAt)';
}

/// Compares two nullable instants ignoring whether either is flagged UTC or
/// local — see the hashCode comment on [Alarm] for why plain `==` is wrong
/// here.
bool _sameInstant(DateTime? a, DateTime? b) {
  if (a == null || b == null) return a == null && b == null;
  return a.isAtSameMomentAs(b);
}
