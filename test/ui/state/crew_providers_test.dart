import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/crew/crew_service.dart';
import 'package:rise/domain/crew_member.dart';
import 'package:rise/domain/crew_state.dart';
import 'package:rise/ui/state/crew_providers.dart';

CrewMember _m(String id, String username) => CrewMember(
    id: id, username: username, displayName: username, avatarColor: '#7C9CF4');

void main() {
  test('unconfigured: crewServiceProvider is DisabledCrewService, crew is empty',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(crewServiceProvider), isA<DisabledCrewService>());
    final state = await container.read(crewProvider.future);
    expect(state.isEmpty, isTrue);
  });

  test('crewProvider streams the (overridden) fake crew', () async {
    final fake = FakeCrewService(directory: [_m('u1', 'ada')]);
    addTearDown(fake.dispose);
    final container = ProviderContainer(overrides: [
      crewServiceProvider.overrideWithValue(fake),
    ]);
    addTearDown(container.dispose);

    final emissions = <CrewState>[];
    final sub = container.listen<AsyncValue<CrewState>>(
      crewProvider,
      (_, next) {
        if (next.hasValue) emissions.add(next.value!);
      },
      fireImmediately: true,
    );
    addTearDown(sub.close);

    await Future<void>.delayed(Duration.zero); // initial empty
    await fake.sendRequest('u1');
    await Future<void>.delayed(Duration.zero);

    expect(emissions.any((s) => s.isEmpty), isTrue, reason: 'starts empty');
    expect(emissions.any((s) => s.outgoing.any((m) => m.id == 'u1')), isTrue,
        reason: 'request sent -> outgoing');
  });
}
