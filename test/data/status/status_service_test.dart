import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/status/status_service.dart';
import 'package:rise/domain/crew_status.dart';

void main() {
  group('FakeStatusService', () {
    test('current reflects the seeded map (unmodifiable)', () {
      final svc = FakeStatusService(initial: {'u1': CrewStatus.awake});
      addTearDown(svc.dispose);
      expect(svc.current['u1'], CrewStatus.awake);
      expect(() => svc.current['u2'] = CrewStatus.asleep, throwsUnsupportedError);
    });

    test('publish records the last value and counts calls', () async {
      final svc = FakeStatusService();
      addTearDown(svc.dispose);
      expect(svc.lastPublished, isNull);
      await svc.publish(CrewStatus.asleep);
      await svc.publish(CrewStatus.waking);
      expect(svc.lastPublished, CrewStatus.waking);
      expect(svc.publishCount, 2);
    });

    test('watch emits current then live updates via emitStatus', () async {
      final svc = FakeStatusService();
      addTearDown(svc.dispose);
      final expectation = expectLater(
        svc.watch(),
        emitsInOrder([
          predicate<Map<String, CrewStatus>>((m) => m.isEmpty),
          predicate<Map<String, CrewStatus>>((m) => m['u1'] == CrewStatus.waking),
        ]),
      );
      await Future<void>.delayed(Duration.zero);
      svc.emitStatus('u1', CrewStatus.waking);
      await expectation;
    });
  });

  group('DisabledStatusService', () {
    const svc = DisabledStatusService();
    test('empty + safe: current/watch empty, publish is a no-op', () async {
      expect(svc.current, isEmpty);
      expect(await svc.watch().first, isEmpty);
      await svc.publish(CrewStatus.awake); // must not throw
    });
  });
}
