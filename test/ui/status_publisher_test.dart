import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/auth/auth_service.dart';
import 'package:rise/data/status/status_service.dart';
import 'package:rise/domain/crew_status.dart';
import 'package:rise/domain/wake_event.dart';
import 'package:rise/ui/state/alarm_providers.dart';
import 'package:rise/ui/state/auth_providers.dart';
import 'package:rise/ui/state/status_providers.dart';
import 'package:rise/ui/state/wake_providers.dart';
import 'package:rise/ui/status_publisher.dart';

WakeEvent _openEvent() => WakeEvent(
      id: 1,
      alarmId: 1,
      scheduledAt: DateTime.utc(2026, 7, 18, 6),
      firstRingAt: DateTime.utc(2026, 7, 18, 6),
    ); // dismissedAt == null -> open -> deriveStatus returns waking regardless of `now`

void main() {
  group('StatusPublisher (dedup)', () {
    test('maybePublish only publishes on a changed value', () async {
      final fake = FakeStatusService();
      addTearDown(fake.dispose);
      final pub = StatusPublisher(fake);
      await pub.maybePublish(CrewStatus.asleep);
      await pub.maybePublish(CrewStatus.asleep); // dup -> skipped
      await pub.maybePublish(CrewStatus.awake);
      expect(fake.publishCount, 2);
      expect(fake.lastPublished, CrewStatus.awake);
    });

    test('republish re-sends the last value (and no-ops before any publish)',
        () async {
      final fake = FakeStatusService();
      addTearDown(fake.dispose);
      final pub = StatusPublisher(fake);
      await pub.republish();
      expect(fake.publishCount, 0);
      await pub.maybePublish(CrewStatus.waking);
      await pub.republish();
      expect(fake.publishCount, 2);
    });
  });

  group('StatusPublisherHost', () {
    testWidgets('publishes the derived status when signed in', (t) async {
      final auth = FakeAuthService();
      await auth.signInWithGoogle();
      await auth.claimUsername('me', displayName: 'Me');
      addTearDown(auth.dispose);
      final status = FakeStatusService();
      addTearDown(status.dispose);

      await t.pumpWidget(ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(auth),
          statusServiceProvider.overrideWithValue(status),
          wakeEventsProvider.overrideWith((ref) => Stream.value([_openEvent()])),
          nextOccurrenceProvider.overrideWith((ref) async => null),
        ],
        child: const MaterialApp(
            home: StatusPublisherHost(child: SizedBox())),
      ));
      await t.pumpAndSettle();
      expect(status.lastPublished, CrewStatus.waking);
    });

    testWidgets('does not publish when signed out', (t) async {
      final status = FakeStatusService();
      addTearDown(status.dispose);
      await t.pumpWidget(ProviderScope(
        overrides: [statusServiceProvider.overrideWithValue(status)],
        child: const MaterialApp(
            home: StatusPublisherHost(child: SizedBox())),
      ));
      await t.pumpAndSettle();
      expect(status.publishCount, 0);
    });
  });
}
