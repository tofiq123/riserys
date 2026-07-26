import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/auth/auth_service.dart';
import 'package:rise/data/feed/feed_service.dart';
import 'package:rise/domain/feed_item.dart';
import 'package:rise/domain/rise_account.dart';
import 'package:rise/ui/social_warmup_host.dart';
import 'package:rise/ui/state/auth_providers.dart';
import 'package:rise/ui/state/feed_providers.dart';

class _CountingFeedService extends FakeFeedService {
  int calls = 0;

  @override
  Future<List<FeedItem>> crewFeed() {
    calls++;
    return super.crewFeed();
  }
}

const _account = RiseAccount(
    id: 'u1', username: 'me', displayName: 'Me', avatarColor: '#7C9CF4');

void main() {
  testWidgets('signed in: the host pre-loads social data with no screen open',
      (t) async {
    final auth = FakeAuthService(initialAccount: _account);
    addTearDown(auth.dispose);
    final feed = _CountingFeedService();

    await t.pumpWidget(ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(auth),
        feedServiceProvider.overrideWithValue(feed),
      ],
      child: const MaterialApp(
          home: SocialWarmupHost(child: SizedBox.shrink())),
    ));
    await t.pumpAndSettle();

    expect(feed.calls, 1,
        reason: 'warmup must load the feed before Crew is ever opened');
  });

  testWidgets('signed out: the host loads nothing', (t) async {
    final auth = FakeAuthService();
    addTearDown(auth.dispose);
    final feed = _CountingFeedService();

    await t.pumpWidget(ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(auth),
        feedServiceProvider.overrideWithValue(feed),
      ],
      child: const MaterialApp(
          home: SocialWarmupHost(child: SizedBox.shrink())),
    ));
    await t.pumpAndSettle();

    expect(feed.calls, 0, reason: 'no account — nothing to warm up');
  });
}
