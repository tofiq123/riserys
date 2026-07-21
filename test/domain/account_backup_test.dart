import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/account_backup.dart';
import 'package:rise/domain/alarm.dart';
import 'package:rise/domain/wake_event.dart';

void main() {
  Alarm alarm({
    int id = 1,
    int hour = 6,
    int minute = 30,
    Set<int> days = const {1, 2, 3, 4, 5},
    String mission = 'math',
    String vibrationPattern = 'standard',
    String? missionData,
    DateTime? lastDismissedAt,
    DateTime? snoozedUntil,
  }) =>
      Alarm(
        id: id,
        hour: hour,
        minute: minute,
        days: days,
        enabled: true,
        label: 'Morning',
        soundAsset: 'sounds/x.mp3',
        vibrate: false,
        vibrationPattern: vibrationPattern,
        mission: mission,
        missionDiff: 'hard',
        missionCount: 2,
        missionData: missionData,
        lastDismissedAt: lastDismissedAt,
        snoozedUntil: snoozedUntil,
      );

  WakeEvent event({
    int id = 5,
    int alarmId = 1,
    DateTime? dismissedAt,
    int? alertnessScore,
    String? method = 'mission',
  }) =>
      WakeEvent(
        id: id,
        alarmId: alarmId,
        scheduledAt: DateTime.utc(2026, 7, 18, 6, 30),
        firstRingAt: DateTime.utc(2026, 7, 18, 6, 31),
        dismissedAt: dismissedAt,
        method: method,
        snoozeCount: 2,
        missionFailures: 1,
        onTime: true,
        label: 'Morning',
        alertnessScore: alertnessScore,
      );

  group('encodeBackup', () {
    test(
        'PRIVACY: the payload carries only alarms + wake events — the home '
        'anchor (homeLat/homeLng, a device-local setting) is never included',
        () {
      final map = encodeBackup([alarm()], [event()]);
      // Exactly the three known top-level keys; adding a new one (or leaking a
      // settings field like the home anchor) must be a conscious, reviewed act.
      expect(map.keys.toSet(), {'v', 'alarms', 'wakeEvents'});
      final serialized = jsonEncode(map);
      expect(serialized, isNot(contains('homeLat')));
      expect(serialized, isNot(contains('homeLng')));
      expect(serialized, isNot(contains('homeShare')));
    });

    test('has version 1 and both lists', () {
      final map = encodeBackup([alarm()], [event()]);
      expect(map['v'], 1);
      expect(map['alarms'], isA<List>());
      expect(map['wakeEvents'], isA<List>());
    });

    test('excludes device-local runtime fields', () {
      final map = encodeBackup(
        [
          alarm(
            lastDismissedAt: DateTime.utc(2026, 1, 1),
            snoozedUntil: DateTime.utc(2026, 1, 2),
          )
        ],
        [event(id: 99)],
      );
      final a = (map['alarms'] as List).first as Map;
      expect(a.containsKey('id'), isFalse);
      expect(a.containsKey('lastDismissedAt'), isFalse);
      expect(a.containsKey('snoozedUntil'), isFalse);
      final e = (map['wakeEvents'] as List).first as Map;
      expect(e.containsKey('id'), isFalse);
    });

    test('is JSON-serializable', () {
      final map = encodeBackup([alarm()], [event(dismissedAt: DateTime.utc(2026, 7, 18, 6, 40))]);
      expect(() => jsonEncode(map), returnsNormally);
      // Survives a real JSON round trip (Map<String,dynamic> shape preserved).
      final decoded = jsonDecode(jsonEncode(map)) as Map<String, dynamic>;
      expect(decoded['v'], 1);
    });
  });

  group('decodeBackup round trip', () {
    test('alarms round-trip (id reset to 0, runtime fields dropped)', () {
      final src = alarm(
        missionData: 'QR-PAYLOAD',
        vibrationPattern: 'intense', // a non-default preference must survive
        lastDismissedAt: DateTime.utc(2026, 1, 1),
        snoozedUntil: DateTime.utc(2026, 1, 2),
      );
      final out = decodeBackup(encodeBackup([src], const []));
      expect(out.alarms.length, 1);
      final a = out.alarms.single;
      expect(a.id, 0);
      expect(a.lastDismissedAt, isNull);
      expect(a.snoozedUntil, isNull);
      expect(
        a,
        src.copyWith(
            id: 0, clearLastDismissedAt: true, clearSnoozedUntil: true),
      );
    });

    test('one-shot alarm (empty days) round-trips', () {
      final src = alarm(days: const {});
      final out = decodeBackup(encodeBackup([src], const []));
      expect(out.alarms.single.days, isEmpty);
      expect(out.alarms.single.isOneShot, isTrue);
    });

    test('wake events round-trip (id reset to 0), incl. null dismissedAt', () {
      final finalized = event(dismissedAt: DateTime.utc(2026, 7, 18, 6, 40), alertnessScore: 88);
      final open = event(id: 6, dismissedAt: null, method: null, alertnessScore: null);
      final out = decodeBackup(encodeBackup(const [], [finalized, open]));
      expect(out.wakeEvents.length, 2);
      expect(out.wakeEvents[0].id, 0);
      expect(out.wakeEvents[0], finalized.copyWith(id: 0));
      expect(out.wakeEvents[1], open.copyWith(id: 0));
      expect(out.wakeEvents[1].isOpen, isTrue);
    });

    test('timestamps are preserved as the same instant', () {
      final e = event(dismissedAt: DateTime.utc(2026, 7, 18, 6, 40));
      final out = decodeBackup(encodeBackup(const [], [e]));
      final r = out.wakeEvents.single;
      expect(r.scheduledAt.isAtSameMomentAs(e.scheduledAt), isTrue);
      expect(r.firstRingAt.isAtSameMomentAs(e.firstRingAt), isTrue);
      expect(r.dismissedAt!.isAtSameMomentAs(e.dismissedAt!), isTrue);
      expect(r.scheduledAt.isUtc, isTrue);
    });

    test('empty backup round-trips to empty', () {
      final out = decodeBackup(encodeBackup(const [], const []));
      expect(out.alarms, isEmpty);
      expect(out.wakeEvents, isEmpty);
    });
  });

  group('decodeBackup tolerance', () {
    test('unknown version decodes to empty', () {
      final out = decodeBackup({'v': 99, 'alarms': [{'hour': 6, 'minute': 0}]});
      expect(out.alarms, isEmpty);
      expect(out.wakeEvents, isEmpty);
    });

    test('missing version decodes to empty', () {
      final out = decodeBackup({'alarms': [{'hour': 6, 'minute': 0}]});
      expect(out.alarms, isEmpty);
    });

    test('missing alarms / wakeEvents keys do not throw', () {
      final out = decodeBackup({'v': 1});
      expect(out.alarms, isEmpty);
      expect(out.wakeEvents, isEmpty);
    });

    test('extra unknown fields are ignored', () {
      final out = decodeBackup({
        'v': 1,
        'surprise': true,
        'alarms': [
          {'hour': 7, 'minute': 15, 'weird': 'ignored'}
        ],
        'wakeEvents': const [],
      });
      expect(out.alarms.single.hour, 7);
      expect(out.alarms.single.minute, 15);
    });

    test('missing alarm fields fall back to domain defaults', () {
      final out = decodeBackup({
        'v': 1,
        'alarms': [
          {'hour': 8, 'minute': 5}
        ],
      });
      final a = out.alarms.single;
      expect(a.enabled, isTrue);
      expect(a.label, 'Alarm');
      expect(a.soundAsset, 'sounds/default_alarm.mp3');
      expect(a.vibrate, isTrue);
      expect(a.mission, 'none');
      expect(a.missionDiff, 'easy');
      expect(a.missionCount, 1);
      expect(a.missionData, isNull);
      expect(a.days, isEmpty);
    });

    test('malformed items are skipped, valid ones kept', () {
      final out = decodeBackup({
        'v': 1,
        'alarms': [
          'not-a-map',
          {'minute': 5}, // no hour -> skipped
          {'hour': 30, 'minute': 5}, // out of range -> skipped
          {'hour': 9, 'minute': 0}, // valid
        ],
        'wakeEvents': [
          {'label': 'no timestamps'}, // skipped
          {
            'scheduledAt': '2026-07-18T06:30:00.000Z',
            'firstRingAt': '2026-07-18T06:31:00.000Z',
          },
        ],
      });
      expect(out.alarms.length, 1);
      expect(out.alarms.single.hour, 9);
      expect(out.wakeEvents.length, 1);
    });

    test('missionCount is clamped into 1..3', () {
      final out = decodeBackup({
        'v': 1,
        'alarms': [
          {'hour': 6, 'minute': 0, 'missionCount': 99},
          {'hour': 6, 'minute': 0, 'missionCount': 0},
        ],
      });
      expect(out.alarms[0].missionCount, 3);
      expect(out.alarms[1].missionCount, 1);
    });

    test('non-map payload-ish inputs do not throw', () {
      expect(decodeBackup(const {}).alarms, isEmpty);
      expect(decodeBackup({'v': 1, 'alarms': 'nope'}).alarms, isEmpty);
    });
  });
}
