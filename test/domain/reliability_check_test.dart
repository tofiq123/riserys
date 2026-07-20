import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/reliability_check.dart';

List<ReliabilityCheck> _android({
  bool notif = true,
  bool exact = true,
  bool fsi = true,
  bool batt = true,
}) =>
    buildReliabilityChecks(
      isAndroid: true,
      notifications: notif,
      exactAlarm: exact,
      fullScreenIntent: fsi,
      batteryUnrestricted: batt,
    );

void main() {
  group('buildReliabilityChecks', () {
    test('Android surfaces all five checks, including OEM autostart', () {
      final ids = _android().map((c) => c.id).toList();
      expect(
          ids,
          containsAll([
            ReliabilityCheckId.notifications,
            ReliabilityCheckId.exactAlarm,
            ReliabilityCheckId.fullScreenIntent,
            ReliabilityCheckId.battery,
            ReliabilityCheckId.oemAutostart,
          ]));
      expect(ids.length, 5);
    });

    test('non-Android omits the battery and OEM-autostart rows', () {
      final checks = buildReliabilityChecks(
        isAndroid: false,
        notifications: true,
        exactAlarm: true,
        fullScreenIntent: true,
        batteryUnrestricted: true,
      );
      final ids = checks.map((c) => c.id).toList();
      expect(ids, isNot(contains(ReliabilityCheckId.battery)));
      expect(ids, isNot(contains(ReliabilityCheckId.oemAutostart)));
      expect(ids.length, 3);
    });

    test('granted permissions map to ok, ungranted to needsAttention', () {
      final ok = _android();
      expect(ok.firstWhere((c) => c.id == ReliabilityCheckId.notifications).isOk,
          isTrue);

      final bad = _android(notif: false, batt: false);
      expect(
          bad
              .firstWhere((c) => c.id == ReliabilityCheckId.notifications)
              .needsAttention,
          isTrue);
      expect(
          bad
              .firstWhere((c) => c.id == ReliabilityCheckId.battery)
              .needsAttention,
          isTrue);
    });

    test('OEM autostart is always unknown — never a fabricated pass', () {
      final oem = _android()
          .firstWhere((c) => c.id == ReliabilityCheckId.oemAutostart);
      expect(oem.isUnknown, isTrue);
    });

    test('every check carries a title and a why', () {
      for (final c in _android()) {
        expect(c.title, isNotEmpty);
        expect(c.why, isNotEmpty);
      }
    });
  });

  group('ReliabilitySummary', () {
    test('all granted → score 100, allClear, overall ok is not claimed when '
        'an unknown remains', () {
      final s = ReliabilitySummary(_android());
      // Four definite checks all ok → score 100.
      expect(s.okCount, 4);
      expect(s.attentionCount, 0);
      expect(s.unknownCount, 1); // OEM autostart
      expect(s.score, 100);
      expect(s.allClear, isTrue);
      // Honest: an unknown remains, so overall is unknown, not ok.
      expect(s.overall, ReliabilityStatus.unknown);
      expect(s.headline, contains('double-check'));
    });

    test('a missing permission drives overall to needsAttention', () {
      final s = ReliabilitySummary(_android(batt: false));
      expect(s.attentionCount, 1);
      expect(s.overall, ReliabilityStatus.needsAttention);
      expect(s.allClear, isFalse);
      expect(s.headline, '1 thing needs attention');
    });

    test('two missing permissions pluralise the headline', () {
      final s = ReliabilitySummary(_android(notif: false, exact: false));
      expect(s.headline, '2 things need attention');
    });

    test('score is the ok fraction of definite checks, ignoring unknowns', () {
      // 3 of 4 definite checks ok → 75.
      final s = ReliabilitySummary(_android(batt: false));
      expect(s.score, 75);
    });

    test('non-Android all-ok reads as fully ready', () {
      final checks = buildReliabilityChecks(
        isAndroid: false,
        notifications: true,
        exactAlarm: true,
        fullScreenIntent: true,
        batteryUnrestricted: true,
      );
      final s = ReliabilitySummary(checks);
      expect(s.unknownCount, 0);
      expect(s.overall, ReliabilityStatus.ok);
      expect(s.score, 100);
      expect(s.headline, 'You\'re all set');
    });

    test('empty list is a safe 100 / ok', () {
      const s = ReliabilitySummary([]);
      expect(s.score, 100);
      expect(s.overall, ReliabilityStatus.ok);
    });
  });
}
