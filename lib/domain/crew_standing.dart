import 'wake_stats.dart';

/// One row in the crew leaderboard: a user's public profile + their [stats].
class CrewStanding {
  const CrewStanding({
    required this.id,
    required this.username,
    required this.displayName,
    required this.avatarColor,
    required this.stats,
    this.isMe = false,
  });

  final String id;
  final String username;
  final String displayName;
  final String avatarColor;
  final WakeStats stats;
  final bool isMe;

  CrewStanding copyWith({
    String? id,
    String? username,
    String? displayName,
    String? avatarColor,
    WakeStats? stats,
    bool? isMe,
  }) =>
      CrewStanding(
        id: id ?? this.id,
        username: username ?? this.username,
        displayName: displayName ?? this.displayName,
        avatarColor: avatarColor ?? this.avatarColor,
        stats: stats ?? this.stats,
        isMe: isMe ?? this.isMe,
      );

  @override
  bool operator ==(Object other) =>
      other is CrewStanding &&
      other.id == id &&
      other.username == username &&
      other.displayName == displayName &&
      other.avatarColor == avatarColor &&
      other.stats == stats &&
      other.isMe == isMe;

  @override
  int get hashCode =>
      Object.hash(id, username, displayName, avatarColor, stats, isMe);
}

/// Returns a new list ranked by wake consistency: current streak desc, then
/// best streak desc, then on-time rate desc, then username asc (stable).
List<CrewStanding> rankStandings(List<CrewStanding> input) {
  final list = [...input];
  list.sort((a, b) {
    final byCurrent = b.stats.currentStreak.compareTo(a.stats.currentStreak);
    if (byCurrent != 0) return byCurrent;
    final byBest = b.stats.bestStreak.compareTo(a.stats.bestStreak);
    if (byBest != 0) return byBest;
    final byRate = b.stats.onTimeRate.compareTo(a.stats.onTimeRate);
    if (byRate != 0) return byRate;
    return a.username.compareTo(b.username);
  });
  return list;
}
