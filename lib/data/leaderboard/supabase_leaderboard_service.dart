import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/crew_standing.dart';
import '../../domain/wake_stats.dart';
import 'leaderboard_service.dart';

/// Production [LeaderboardService]: upserts the signed-in user's aggregate wake
/// stats and fetches the crew leaderboard (own + accepted-crew via RLS, ranked).
/// Only constructed when configured, and only off the alarm path. Fetch-on-open
/// (no Realtime).
///
/// NOTE: build-verified only (needs a live backend). Exercised by the two-account
/// leaderboard smoke test in the 5e setup guide.
class SupabaseLeaderboardService implements LeaderboardService {
  SupabaseLeaderboardService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  static const _defaultAvatarColor = '#7C9CF4';

  final SupabaseClient _client;

  int _int(Object? v) => (v as num?)?.toInt() ?? 0;

  @override
  Future<void> publishStats(WakeStats stats) async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return; // not signed in — nothing to publish
    try {
      await _client.from('stats').upsert({
        'user_id': me,
        'current_streak': stats.currentStreak,
        'best_streak': stats.bestStreak,
        'total_wakes': stats.totalWakes,
        'on_time': stats.onTimeCount,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id');
    } catch (_) {
      // best-effort; a publish failure must never surface to the caller
    }
  }

  @override
  Future<List<CrewStanding>> fetchLeaderboard() async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return const [];
    try {
      final statRows = await _client.from('stats').select(
          'user_id, current_streak, best_streak, total_wakes, on_time');
      final ids = <String>[for (final r in statRows) r['user_id'] as String];
      if (ids.isEmpty) return const [];

      final profiles = await _client
          .from('profiles')
          .select('id, username, display_name, avatar_color')
          .inFilter('id', ids);
      final byId = {for (final p in profiles) p['id'] as String: p};

      final standings = <CrewStanding>[];
      for (final r in statRows) {
        final id = r['user_id'] as String;
        final p = byId[id];
        if (p == null) continue; // profile not readable — skip
        standings.add(CrewStanding(
          id: id,
          username: (p['username'] as String?) ?? '',
          displayName: (p['display_name'] as String?) ?? '',
          avatarColor: (p['avatar_color'] as String?) ?? _defaultAvatarColor,
          stats: WakeStats(
            currentStreak: _int(r['current_streak']),
            bestStreak: _int(r['best_streak']),
            totalWakes: _int(r['total_wakes']),
            onTimeCount: _int(r['on_time']),
          ),
          isMe: id == me,
        ));
      }
      return rankStandings(standings);
    } catch (_) {
      return const []; // best-effort
    }
  }
}
