import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/auth/auth_service.dart';
import 'package:rise/data/feed/feed_service.dart';
import 'package:rise/domain/feed_item.dart';
import 'package:rise/ui/state/auth_providers.dart';
import 'package:rise/ui/state/feed_providers.dart';

/// Counts crewFeed() fetches so retention/refetch behaviour is observable.
class _CountingFeedService extends FakeFeedService {
  int calls = 0;

  @override
  Future<List<FeedItem>> crewFeed() {
    calls++;
    return super.crewFeed();
  }
}

void main() {
  test('feed cache survives losing its last listener (no per-visit refetch)',
      () async {
    final service = _CountingFeedService();
    final container = ProviderContainer(
        overrides: [feedServiceProvider.overrideWithValue(service)]);
    addTearDown(container.dispose);

    final sub = container.listen(crewFeedProvider, (_, __) {});
    await container.read(crewFeedProvider.future);
    expect(service.calls, 1);

    // The Crew tab unmounting drops the last listener. The cache must live on.
    sub.close();
    await Future<void>.delayed(Duration.zero);

    container.listen(crewFeedProvider, (_, __) {});
    await container.read(crewFeedProvider.future);
    expect(service.calls, 1, reason: 'cached — reopening must not refetch');
  });

  test('feed re-fetches when the signed-in account changes', () async {
    final service = _CountingFeedService();
    final auth = FakeAuthService();
    addTearDown(auth.dispose);
    final container = ProviderContainer(overrides: [
      feedServiceProvider.overrideWithValue(service),
      authServiceProvider.overrideWithValue(auth),
    ]);
    addTearDown(container.dispose);

    container.listen(crewFeedProvider, (_, __) {});
    await container.read(crewFeedProvider.future);
    expect(service.calls, 1);

    await auth.signInWithGoogle();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    await container.read(crewFeedProvider.future);
    expect(service.calls, 2,
        reason: 'a new account id must invalidate the cached feed');
  });
}
