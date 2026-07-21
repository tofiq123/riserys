// The crew activity feed: one [FeedItem] per celebrated wake, each carrying a
// summary of the emoji [FeedReaction]s its crew left. Pure data + the grouping
// logic that turns raw reaction rows into a per-emoji summary — no I/O here.

/// The emoji palette the UI offers for reactions, in display order. Warm and
/// pro-social by design — every option celebrates a wake, none shames a miss.
const List<String> kFeedReactionEmojis = ['🔥', '👏', '💪', '☀️'];

/// One emoji's tally on a feed item: how many crew members used it, and whether
/// the signed-in user is one of them (drives the toggle state in the UI).
class FeedReaction {
  const FeedReaction({
    required this.emoji,
    required this.count,
    required this.reactedByMe,
  });

  final String emoji;
  final int count;
  final bool reactedByMe;

  FeedReaction copyWith({String? emoji, int? count, bool? reactedByMe}) =>
      FeedReaction(
        emoji: emoji ?? this.emoji,
        count: count ?? this.count,
        reactedByMe: reactedByMe ?? this.reactedByMe,
      );

  @override
  bool operator ==(Object other) =>
      other is FeedReaction &&
      other.emoji == emoji &&
      other.count == count &&
      other.reactedByMe == reactedByMe;

  @override
  int get hashCode => Object.hash(emoji, count, reactedByMe);

  @override
  String toString() =>
      'FeedReaction($emoji x$count${reactedByMe ? ', mine' : ''})';
}

/// One celebrated wake in the crew feed: who woke, when, whether on time, the
/// streak it landed, and the reaction summary. [isMe] marks the signed-in user's
/// own item. Reactions only include emojis with at least one reactor; the UI
/// overlays the full [kFeedReactionEmojis] palette via [reactionFor].
class FeedItem {
  const FeedItem({
    required this.id,
    required this.userId,
    required this.username,
    required this.displayName,
    required this.avatarColor,
    required this.wokeAt,
    required this.onTime,
    required this.streak,
    this.isMe = false,
    this.reactions = const [],
  });

  final String id;
  final String userId;
  final String username;
  final String displayName;
  final String avatarColor;

  /// The instant the user finished waking (dismissed the alarm), in UTC.
  final DateTime wokeAt;
  final bool onTime;
  final int streak;
  final bool isMe;

  /// Per-emoji summary — only emojis with a count >= 1, newest-agnostic order
  /// (see [summarizeReactions]).
  final List<FeedReaction> reactions;

  /// The tally for [emoji], or a zero-count / not-reacted default when no one
  /// has used it — so the UI can render the fixed palette row uniformly.
  FeedReaction reactionFor(String emoji) {
    for (final r in reactions) {
      if (r.emoji == emoji) return r;
    }
    return FeedReaction(emoji: emoji, count: 0, reactedByMe: false);
  }

  FeedItem copyWith({
    String? id,
    String? userId,
    String? username,
    String? displayName,
    String? avatarColor,
    DateTime? wokeAt,
    bool? onTime,
    int? streak,
    bool? isMe,
    List<FeedReaction>? reactions,
  }) =>
      FeedItem(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        username: username ?? this.username,
        displayName: displayName ?? this.displayName,
        avatarColor: avatarColor ?? this.avatarColor,
        wokeAt: wokeAt ?? this.wokeAt,
        onTime: onTime ?? this.onTime,
        streak: streak ?? this.streak,
        isMe: isMe ?? this.isMe,
        reactions: reactions ?? this.reactions,
      );

  @override
  bool operator ==(Object other) =>
      other is FeedItem &&
      other.id == id &&
      other.userId == userId &&
      other.username == username &&
      other.displayName == displayName &&
      other.avatarColor == avatarColor &&
      other.wokeAt.isAtSameMomentAs(wokeAt) &&
      other.onTime == onTime &&
      other.streak == streak &&
      other.isMe == isMe &&
      _listEq(other.reactions, reactions);

  @override
  int get hashCode => Object.hash(id, userId, username, displayName, avatarColor,
      wokeAt.toUtc(), onTime, streak, isMe, Object.hashAll(reactions));

  @override
  String toString() =>
      'FeedItem(id: $id, user: @$username, wokeAt: ${wokeAt.toIso8601String()}, '
      'onTime: $onTime, streak: $streak, reactions: $reactions)';
}

bool _listEq(List<FeedReaction> a, List<FeedReaction> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// One raw reaction row as stored: which emoji, by whom.
typedef RawReaction = ({String emoji, String reactorId});

/// Folds raw reaction rows into a per-emoji [FeedReaction] summary: counts each
/// distinct emoji and flags whether [myId] is among its reactors. Pure and
/// deterministic. Ordering: palette emojis first in [kFeedReactionEmojis] order,
/// then any other emoji; ties broken by count desc then emoji, so the same input
/// always yields the same list (stable UI, testable).
List<FeedReaction> summarizeReactions(
  Iterable<RawReaction> raw, {
  required String? myId,
}) {
  final counts = <String, int>{};
  final mine = <String, bool>{};
  for (final r in raw) {
    counts[r.emoji] = (counts[r.emoji] ?? 0) + 1;
    if (myId != null && r.reactorId == myId) mine[r.emoji] = true;
  }

  final result = [
    for (final entry in counts.entries)
      FeedReaction(
        emoji: entry.key,
        count: entry.value,
        reactedByMe: mine[entry.key] ?? false,
      ),
  ];

  int paletteRank(String emoji) {
    final i = kFeedReactionEmojis.indexOf(emoji);
    return i == -1 ? kFeedReactionEmojis.length : i;
  }

  result.sort((a, b) {
    final byPalette = paletteRank(a.emoji).compareTo(paletteRank(b.emoji));
    if (byPalette != 0) return byPalette;
    final byCount = b.count.compareTo(a.count);
    if (byCount != 0) return byCount;
    return a.emoji.compareTo(b.emoji);
  });
  return result;
}
