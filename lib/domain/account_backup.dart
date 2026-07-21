// Serialization for the per-account cloud backup (see the account-sync spec and
// migration 0008). The payload is a single JSON blob per user:
//
//   { "v": 1, "alarms": [ ... ], "wakeEvents": [ ... ] }
//
// Pure and side-effect free so it is trivially unit-testable. Device-local
// runtime fields are intentionally EXCLUDED — an alarm's `lastDismissedAt` /
// `snoozedUntil` and a wake event's local autoincrement `id` are meaningless on
// another device, so they never leave the device and are never restored.
//
// Decode is deliberately tolerant: a missing field falls back to the domain
// default, an unknown/corrupt item is skipped rather than throwing, and an
// unrecognised `v` decodes to an empty backup. A backup blob must never crash
// the app or the restore flow.

import 'alarm.dart';
import 'wake_event.dart';

/// The only payload version this app writes.
const int kBackupVersion = 1;

/// Serializes local [alarms] + [wakeEvents] into the backup payload map.
Map<String, dynamic> encodeBackup(
  List<Alarm> alarms,
  List<WakeEvent> wakeEvents,
) {
  return {
    'v': kBackupVersion,
    'alarms': [for (final a in alarms) _encodeAlarm(a)],
    'wakeEvents': [for (final e in wakeEvents) _encodeWakeEvent(e)],
  };
}

/// Decodes a backup payload back into alarms + wake events. Alarms come back with
/// `id: 0` (so a restore inserts them fresh) and no runtime fields; wake events
/// come back with `id: 0` for the same reason. Tolerant: never throws on a
/// missing/extra field, skips malformed items, and returns an empty result for
/// an unknown version.
({List<Alarm> alarms, List<WakeEvent> wakeEvents}) decodeBackup(
  Map<String, dynamic> map,
) {
  final version = _asInt(map['v']);
  if (version != kBackupVersion) {
    return (alarms: const <Alarm>[], wakeEvents: const <WakeEvent>[]);
  }

  final alarms = <Alarm>[];
  final rawAlarms = map['alarms'];
  if (rawAlarms is List) {
    for (final item in rawAlarms) {
      final a = _decodeAlarm(item);
      if (a != null) alarms.add(a);
    }
  }

  final wakeEvents = <WakeEvent>[];
  final rawEvents = map['wakeEvents'];
  if (rawEvents is List) {
    for (final item in rawEvents) {
      final e = _decodeWakeEvent(item);
      if (e != null) wakeEvents.add(e);
    }
  }

  return (alarms: alarms, wakeEvents: wakeEvents);
}

// ── Alarm ──────────────────────────────────────────────────────────────────

Map<String, dynamic> _encodeAlarm(Alarm a) => {
      'hour': a.hour,
      'minute': a.minute,
      'days': (a.days.toList()..sort()),
      'enabled': a.enabled,
      'label': a.label,
      'soundAsset': a.soundAsset,
      'vibrate': a.vibrate,
      'mission': a.mission,
      'missionDiff': a.missionDiff,
      'missionCount': a.missionCount,
      'missionData': a.missionData,
    };

/// Returns null (and the caller skips the item) when the entry is not a map or
/// carries an out-of-range time that the [Alarm] invariants would reject.
Alarm? _decodeAlarm(Object? item) {
  if (item is! Map) return null;
  final map = item.cast<String, dynamic>();

  final hour = _asInt(map['hour']);
  final minute = _asInt(map['minute']);
  if (hour == null || minute == null) return null;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;

  return Alarm(
    id: 0,
    hour: hour,
    minute: minute,
    days: _asDays(map['days']),
    enabled: _asBool(map['enabled']) ?? true,
    label: _asString(map['label']) ?? 'Alarm',
    soundAsset: _asString(map['soundAsset']) ?? 'sounds/default_alarm.mp3',
    vibrate: _asBool(map['vibrate']) ?? true,
    mission: _asString(map['mission']) ?? 'none',
    missionDiff: _asString(map['missionDiff']) ?? 'easy',
    missionCount: (_asInt(map['missionCount']) ?? 1).clamp(1, 3),
    missionData: _asString(map['missionData']),
    // lastDismissedAt / snoozedUntil are runtime-only — never restored.
  );
}

// ── WakeEvent ────────────────────────────────────────────────────────────────

Map<String, dynamic> _encodeWakeEvent(WakeEvent e) => {
      'alarmId': e.alarmId,
      'scheduledAt': e.scheduledAt.toUtc().toIso8601String(),
      'firstRingAt': e.firstRingAt.toUtc().toIso8601String(),
      'dismissedAt': e.dismissedAt?.toUtc().toIso8601String(),
      'method': e.method,
      'snoozeCount': e.snoozeCount,
      'missionFailures': e.missionFailures,
      'onTime': e.onTime,
      'label': e.label,
      'alertnessScore': e.alertnessScore,
    };

/// Returns null (item skipped) when the entry is not a map or is missing the two
/// timestamps that define a firing.
WakeEvent? _decodeWakeEvent(Object? item) {
  if (item is! Map) return null;
  final map = item.cast<String, dynamic>();

  final scheduledAt = _parseUtc(map['scheduledAt']);
  final firstRingAt = _parseUtc(map['firstRingAt']);
  if (scheduledAt == null || firstRingAt == null) return null;

  return WakeEvent(
    id: 0,
    alarmId: _asInt(map['alarmId']) ?? 0,
    scheduledAt: scheduledAt,
    firstRingAt: firstRingAt,
    dismissedAt: _parseUtc(map['dismissedAt']),
    method: _asString(map['method']),
    snoozeCount: _asInt(map['snoozeCount']) ?? 0,
    missionFailures: _asInt(map['missionFailures']) ?? 0,
    onTime: _asBool(map['onTime']) ?? false,
    label: _asString(map['label']) ?? 'Alarm',
    alertnessScore: _asInt(map['alertnessScore']),
  );
}

// ── tolerant readers ─────────────────────────────────────────────────────────

int? _asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

bool? _asBool(Object? v) => v is bool ? v : null;

String? _asString(Object? v) => v is String ? v : null;

Set<int> _asDays(Object? v) {
  if (v is! List) return const {};
  final out = <int>{};
  for (final d in v) {
    final n = _asInt(d);
    if (n != null && n >= 0 && n <= 6) out.add(n);
  }
  return out;
}

DateTime? _parseUtc(Object? v) {
  if (v is! String) return null;
  final parsed = DateTime.tryParse(v);
  return parsed?.toUtc();
}
