import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/alarm.dart';
import 'package:rise/ui/missions/mission_host.dart';
import 'package:rise/ui/missions/qr_mission.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  group('qrMatches', () {
    test('an exact match dismisses', () {
      expect(qrMatches('RISE-123', 'RISE-123'), isTrue);
    });

    test('a different code does not match', () {
      expect(qrMatches('RISE-123', 'RISE-999'), isFalse);
    });

    test('leading/trailing whitespace is tolerated on both sides', () {
      expect(qrMatches('  RISE-123 ', 'RISE-123'), isTrue);
      expect(qrMatches('RISE-123', ' RISE-123\n'), isTrue);
    });

    test('a null or empty registered code accepts ANY scan (never a trap)', () {
      expect(qrMatches(null, 'anything'), isTrue);
      expect(qrMatches('', 'anything'), isTrue);
      expect(qrMatches('   ', 'anything'), isTrue);
    });

    test('the match is case-sensitive (QR payloads are exact)', () {
      expect(qrMatches('RISE-abc', 'RISE-ABC'), isFalse);
    });
  });

  group('buildMission host (non-rendering: camera cannot render headlessly)', () {
    testWidgets('dispatches to QrMission carrying the registered code',
        (t) async {
      late BuildContext ctx;
      await t.pumpWidget(_wrap(Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      })));
      final w = buildMission(
          ctx,
          const Alarm(
              id: 1, hour: 6, minute: 0, mission: 'qr', missionData: 'RISE-42'),
          () {});
      expect(w, isA<QrMission>());
      expect((w as QrMission).expected, 'RISE-42');
    });

    testWidgets('an unconfigured qr alarm passes a null expected code',
        (t) async {
      late BuildContext ctx;
      await t.pumpWidget(_wrap(Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      })));
      final w = buildMission(
          ctx, const Alarm(id: 1, hour: 6, minute: 0, mission: 'qr'), () {});
      expect((w as QrMission).expected, isNull);
    });
  });
}
