import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/nudge/nudge_service.dart';

void main() {
  group('FakeNudgeService', () {
    test('nudge records the target and counts calls', () async {
      final svc = FakeNudgeService();
      expect(svc.lastNudged, isNull);
      await svc.nudge('u1');
      await svc.nudge('u2');
      expect(svc.lastNudged, 'u2');
      expect(svc.nudgeCount, 2);
    });

    test('nudge throws NudgeException when configured to fail', () async {
      final svc = FakeNudgeService(failWith: 'Too soon — wait a minute.');
      await expectLater(svc.nudge('u1'), throwsA(isA<NudgeException>()));
      expect(svc.nudgeCount, 0);
    });
  });

  group('DisabledNudgeService', () {
    test('nudge is a harmless no-op', () async {
      const svc = DisabledNudgeService();
      await svc.nudge('u1'); // must not throw
    });
  });
}
