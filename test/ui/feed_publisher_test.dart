import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/auth/auth_service.dart';
import 'package:rise/data/feed/feed_service.dart';
import 'package:rise/domain/wake_event.dart';
import 'package:rise/ui/feed_publisher.dart';
import 'package:rise/ui/state/auth_providers.dart';
import 'package:rise/ui/state/feed_providers.dart';
import 'package:rise/ui/state/wake_providers.dart';

WakeEvent _onTime(int id) => WakeEvent(
      id: id,
      alarmId: 1,
      scheduledAt: DateTime.utc(2026, 7, 20, 6),
      firstRingAt: DateTime.utc(2026, 7, 20, 6),
      dismissedAt: DateTime.utc(2026, 7, 20, 6, 3),
      onTime: true,
    );

WakeEvent _openMiss(int id) => WakeEvent(
      id: id,
      alarmId: 1,
      scheduledAt: DateTime.utc(2026, 7, 20, 6),
      firstRingAt: DateTime.utc(2026, 7, 20, 6),
    ); // no dismissedAt -> not finalized

void main() {
  group('FeedPublisher (dedup)', () {
    test('publishes a finalized wake once, skips repeats of the same id',
        () async {
      final fake = FakeFeedService();
      final pub = FeedPublisher(fake);
      await pub.maybePublish(_onTime(1), streak: 4);
      await pub.maybePublish(_onTime(1), streak: 4); // same id -> skipped
      await pub.maybePublish(_onTime(2), streak: 5);
      expect(fake.published, hasLength(2));
      expect(fake.published.first.streak, 4);
      expect(fake.published.last.streak, 5);
    });

    test('ignores a null event and a non-finalized (open) event', () async {
      final fake = FakeFeedService();
      final pub = FeedPublisher(fake);
      await pub.maybePublish(null, streak: 1);
      await pub.maybePublish(_openMiss(9), streak: 1);
      expect(fake.published, isEmpty);
    });

    test('forwards the dismissal instant and on-time flag', () async {
      final fake = FakeFeedService();
      final pub = FeedPublisher(fake);
      await pub.maybePublish(_onTime(1), streak: 7);
      expect(fake.published.single.wokeAt,
          DateTime.utc(2026, 7, 20, 6, 3));
      expect(fake.published.single.onTime, isTrue);
    });
  });

  group('FeedPublisherHost', () {
    testWidgets('posts the latest on-time wake when signed in', (t) async {
      final auth = FakeAuthService();
      await auth.signInWithGoogle();
      await auth.claimUsername('me', displayName: 'Me');
      addTearDown(auth.dispose);
      final feed = FakeFeedService();

      await t.pumpWidget(ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(auth),
          feedServiceProvider.overrideWithValue(feed),
          wakeEventsProvider.overrideWith((ref) => Stream.value([_onTime(1)])),
          excusedDaysProvider
              .overrideWith((ref) => Stream.value(<DateTime>{})),
        ],
        child: const MaterialApp(home: FeedPublisherHost(child: SizedBox())),
      ));
      await t.pumpAndSettle();
      expect(feed.published, hasLength(1));
      expect(feed.published.single.onTime, isTrue);
    });

    testWidgets('does not post when signed out', (t) async {
      final feed = FakeFeedService();
      await t.pumpWidget(ProviderScope(
        overrides: [
          feedServiceProvider.overrideWithValue(feed),
          wakeEventsProvider.overrideWith((ref) => Stream.value([_onTime(1)])),
          excusedDaysProvider
              .overrideWith((ref) => Stream.value(<DateTime>{})),
        ],
        child: const MaterialApp(home: FeedPublisherHost(child: SizedBox())),
      ));
      await t.pumpAndSettle();
      expect(feed.published, isEmpty);
    });
  });
}
