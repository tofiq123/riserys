import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/wake_event.dart';
import 'package:rise/ui/state/wake_providers.dart';

void main() {
  test('streakProvider is empty with no events', () async {
    final c = ProviderContainer(overrides: [
      wakeEventsProvider.overrideWith((ref) => Stream.value(const <WakeEvent>[])),
    ]);
    addTearDown(c.dispose);
    await c.read(wakeEventsProvider.future);
    expect(c.read(streakProvider).current, 0);
  });

  test('streakProvider counts an on-time event today as a streak of 1', () async {
    final today = DateTime.now();
    final e = WakeEvent(
      id: 1,
      alarmId: 1,
      scheduledAt: today,
      firstRingAt: today,
      dismissedAt: today.add(const Duration(minutes: 2)),
      onTime: true,
    );
    final c = ProviderContainer(overrides: [
      wakeEventsProvider.overrideWith((ref) => Stream.value([e])),
    ]);
    addTearDown(c.dispose);
    await c.read(wakeEventsProvider.future);
    expect(c.read(streakProvider).current, 1);
  });
}
