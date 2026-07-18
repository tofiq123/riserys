import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/nudge/nudge_service.dart';
import 'package:rise/ui/state/nudge_providers.dart';

void main() {
  test('unconfigured: nudgeServiceProvider is DisabledNudgeService', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(nudgeServiceProvider), isA<DisabledNudgeService>());
  });

  test('can be overridden with a fake', () async {
    final fake = FakeNudgeService();
    final container = ProviderContainer(overrides: [
      nudgeServiceProvider.overrideWithValue(fake),
    ]);
    addTearDown(container.dispose);
    await container.read(nudgeServiceProvider).nudge('u1');
    expect(fake.lastNudged, 'u1');
  });
}
