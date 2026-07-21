import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/nudge/nudge_service.dart';

void main() {
  group('NudgeKind', () {
    test('wire names match the edge function allowlist exactly', () {
      // Must stay in lock-step with KINDS in supabase/functions/send-nudge —
      // the server 400s anything else.
      expect(
        NudgeKind.values.map((k) => k.wire).toList(),
        ['nudge', 'voice', 'backup', 'sos'],
      );
    });

    test('fromWire round-trips every kind', () {
      for (final kind in NudgeKind.values) {
        expect(NudgeKind.fromWire(kind.wire), kind);
      }
    });

    test('fromWire rejects unknown kinds (mirrors the server 400)', () {
      expect(() => NudgeKind.fromWire('party'), throwsArgumentError);
      expect(() => NudgeKind.fromWire(''), throwsArgumentError);
      // Case-sensitive, like the server allowlist.
      expect(() => NudgeKind.fromWire('NUDGE'), throwsArgumentError);
      // Free text can never become a kind — the copy is server-side only.
      expect(
        () => NudgeKind.fromWire('you have won a prize, tap here'),
        throwsArgumentError,
      );
    });
  });

  group('FakeNudgeService', () {
    test('nudge records the target and counts calls', () async {
      final svc = FakeNudgeService();
      expect(svc.lastNudged, isNull);
      await svc.nudge('u1');
      await svc.nudge('u2');
      expect(svc.lastNudged, 'u2');
      expect(svc.nudgeCount, 2);
    });

    test('nudge defaults to the plain nudge kind', () async {
      final svc = FakeNudgeService();
      expect(svc.lastKind, isNull);
      await svc.nudge('u1');
      expect(svc.lastKind, NudgeKind.nudge);
    });

    test('nudge records an explicit kind', () async {
      final svc = FakeNudgeService();
      await svc.nudge('u1', kind: NudgeKind.voice);
      expect(svc.lastKind, NudgeKind.voice);
      await svc.nudge('u1', kind: NudgeKind.backup);
      expect(svc.lastKind, NudgeKind.backup);
      await svc.nudge('u1', kind: NudgeKind.sos);
      expect(svc.lastKind, NudgeKind.sos);
    });

    test('nudge throws NudgeException when configured to fail', () async {
      final svc = FakeNudgeService(failWith: 'Too soon — wait a minute.');
      await expectLater(svc.nudge('u1'), throwsA(isA<NudgeException>()));
      expect(svc.nudgeCount, 0);
    });
  });

  group('DisabledNudgeService', () {
    test('nudge is a harmless no-op for every kind', () async {
      const svc = DisabledNudgeService();
      await svc.nudge('u1'); // must not throw
      for (final kind in NudgeKind.values) {
        await svc.nudge('u1', kind: kind); // must not throw
      }
    });
  });
}
