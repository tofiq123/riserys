import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/feed_item.dart';
import 'feed_service.dart';

/// Production [FeedService]: feed items in `public.wake_feed`, reactions in
/// `public.feed_reactions` (RLS in migration 0009 scopes both to own + accepted
/// friends). Fetch-on-open (no Realtime), mirroring the leaderboard. Only
/// constructed when configured, and posting runs off the alarm path.
///
/// NOTE: build-verified only (needs a live backend). Exercised by the two-account
/// post/react smoke test in the Phase 17 setup guide.
class SupabaseFeedService implements FeedService {
  SupabaseFeedService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  static const _defaultAvatarColor = '#7C9CF4';

  /// How many recent feed items to pull on open.
  static const _feedLimit = 50;

  final SupabaseClient _client;

  int _int(Object? v) => (v as num?)?.toInt() ?? 0;

  @override
  Future<void> publishWake({
    required DateTime wokeAt,
    required bool onTime,
    required int streak,
  }) async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return; // not signed in — nothing to publish
    try {
      // Idempotent per (user_id, woke_at): a re-post of the same wake (e.g. on a
      // later cold start) hits the unique constraint and is ignored, never
      // duplicated. ignoreDuplicates keeps the first post's on_time/streak.
      await _client.from('wake_feed').upsert({
        'user_id': me,
        'woke_at': wokeAt.toUtc().toIso8601String(),
        'on_time': onTime,
        'streak': streak,
      }, onConflict: 'user_id, woke_at', ignoreDuplicates: true);
    } catch (_) {
      // best-effort; a publish failure must never surface to the caller
    }
  }

  @override
  Future<List<FeedItem>> crewFeed() async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return const [];
    try {
      final rows = await _client
          .from('wake_feed')
          .select('id, user_id, woke_at, on_time, streak')
          .order('created_at', ascending: false)
          .limit(_feedLimit);
      if (rows.isEmpty) return const [];

      final feedIds = <String>[for (final r in rows) r['id'] as String];
      final userIds =
          <String>{for (final r in rows) r['user_id'] as String}.toList();

      // Profiles for the authors (RLS: own + friends are readable).
      final profiles = await _client
          .from('profiles')
          .select('id, username, display_name, avatar_color')
          .inFilter('id', userIds);
      final byId = {for (final p in profiles) p['id'] as String: p};

      // Reactions on those items (RLS returns only reactions on visible items).
      final reactionRows = await _client
          .from('feed_reactions')
          .select('feed_id, reactor_id, emoji')
          .inFilter('feed_id', feedIds);
      final byFeed = <String, List<RawReaction>>{};
      for (final r in reactionRows) {
        final fid = r['feed_id'] as String;
        (byFeed[fid] ??= []).add((
          emoji: (r['emoji'] as String?) ?? '',
          reactorId: (r['reactor_id'] as String?) ?? '',
        ));
      }

      final items = <FeedItem>[];
      for (final r in rows) {
        final id = r['id'] as String;
        final userId = r['user_id'] as String;
        final p = byId[userId];
        if (p == null) continue; // author profile not readable — skip
        items.add(FeedItem(
          id: id,
          userId: userId,
          username: (p['username'] as String?) ?? '',
          displayName: (p['display_name'] as String?) ?? '',
          avatarColor: (p['avatar_color'] as String?) ?? _defaultAvatarColor,
          wokeAt: DateTime.parse(r['woke_at'] as String),
          onTime: (r['on_time'] as bool?) ?? false,
          streak: _int(r['streak']),
          isMe: userId == me,
          reactions: summarizeReactions(byFeed[id] ?? const [], myId: me),
        ));
      }
      return items;
    } catch (_) {
      return const []; // best-effort
    }
  }

  @override
  Future<void> react(String feedId, String emoji) async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return;
    try {
      // Idempotent: the unique(feed_id, reactor_id, emoji) constraint turns a
      // double-tap into a no-op instead of a duplicate row.
      await _client.from('feed_reactions').upsert({
        'feed_id': feedId,
        'reactor_id': me,
        'emoji': emoji,
      }, onConflict: 'feed_id, reactor_id, emoji', ignoreDuplicates: true);
    } catch (_) {
      // best-effort; the UI refetches and reconciles the true state
    }
  }

  @override
  Future<void> unreact(String feedId, String emoji) async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return;
    try {
      await _client
          .from('feed_reactions')
          .delete()
          .eq('feed_id', feedId)
          .eq('reactor_id', me)
          .eq('emoji', emoji);
    } catch (_) {
      // best-effort; the UI refetches and reconciles the true state
    }
  }
}
