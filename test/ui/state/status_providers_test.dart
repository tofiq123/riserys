import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/status/status_service.dart';
import 'package:rise/domain/crew_status.dart';
import 'package:rise/ui/state/status_providers.dart';

void main() {
  test('unconfigured: statusServiceProvider is DisabledStatusService, statuses empty',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(statusServiceProvider), isA<DisabledStatusService>());
    final map = await container.read(crewStatusesProvider.future);
    expect(map, isEmpty);
  });

  test('crewStatusesProvider streams the (overridden) fake', () async {
    final fake = FakeStatusService();
    addTearDown(fake.dispose);
    final container = ProviderContainer(overrides: [
      statusServiceProvider.overrideWithValue(fake),
    ]);
    addTearDown(container.dispose);

    final emissions = <Map<String, CrewStatus>>[];
    final sub = container.listen<AsyncValue<Map<String, CrewStatus>>>(
      crewStatusesProvider,
      (_, next) {
        if (next.hasValue) emissions.add(next.value!);
      },
      fireImmediately: true,
    );
    addTearDown(sub.close);

    await Future<void>.delayed(Duration.zero);
    fake.emitStatus('u1', CrewStatus.waking);
    await Future<void>.delayed(Duration.zero);

    expect(emissions.any((m) => m.isEmpty), isTrue, reason: 'starts empty');
    expect(emissions.any((m) => m['u1'] == CrewStatus.waking), isTrue);
  });
}
