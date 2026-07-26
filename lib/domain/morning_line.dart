import 'crew_member.dart';
import 'crew_status.dart';
import 'feed_item.dart';

/// Which shape the Crew tab takes right now.
///
/// The whole product is about one moment in the day, so the screen is allowed
/// to be a different screen at 06:12 than at 22:40. Derived, never stored.
enum MorningPhase {
  /// The morning is happening. Live count, NOW marker, people still to come.
  window,

  /// The morning is a record. No marker; everyone is above the line, including
  /// whoever never woke.
  wrapped,

  /// Bedtime. The only useful fact is your own next alarm.
  tonight,
}

/// Local hour from which the morning stops being the subject.
const int _nightFromHour = 21;

/// Local hour before which a new day is still "tonight" rather than a window
/// that opened absurdly early.
const int _nightUntilHour = 4;

/// A morning stays live for this long after the most recent wake — long enough
/// that a late riser still lands in a window the crew can cheer.
const Duration _liveAfterLastWake = Duration(hours: 3);

/// Before this hour the window is open even with nothing logged: the mornings
/// simply haven't happened yet.
const int _windowUntilHour = 10;

/// Picks the phase. Rules are applied in order; the first match wins.
///
/// [todayWakes] are the wake instants already logged for the local day;
/// [statuses] the crew's live presence. Neither needs to be sorted.
MorningPhase phaseFor({
  required DateTime now,
  required List<DateTime> todayWakes,
  required Iterable<CrewStatus> statuses,
}) {
  final local = now.toLocal();

  // 1. Night. Nothing about this morning is actionable any more.
  if (local.hour >= _nightFromHour || local.hour < _nightUntilHour) {
    return MorningPhase.tonight;
  }

  // 2. Someone is mid-mission right now — the most live the app ever gets.
  if (statuses.any((s) => s == CrewStatus.waking)) return MorningPhase.window;

  // 3. A wake landed recently enough that cheering it still makes sense.
  if (todayWakes.isNotEmpty) {
    final last = todayWakes.reduce((a, b) => a.isAfter(b) ? a : b).toLocal();
    // Guard against a future timestamp from clock skew: never negative.
    if (!local.isBefore(last) &&
        local.difference(last) <= _liveAfterLastWake) {
      return MorningPhase.window;
    }
  }

  // 4. Early, with nothing logged: the mornings are still ahead.
  if (local.hour < _windowUntilHour) return MorningPhase.window;

  // 5. The window has come and gone.
  return MorningPhase.wrapped;
}

/// One row on the Morning Line: a person, and what their morning did.
class MorningEntry {
  const MorningEntry({
    required this.id,
    required this.username,
    required this.displayName,
    required this.avatarColor,
    required this.status,
    this.wokeAt,
    this.onTime = false,
    this.streak = 0,
    this.isMe = false,
    this.feedId,
    this.reactions = const [],
  });

  final String id;
  final String username;
  final String displayName;
  final String avatarColor;

  /// When they finished waking, or null while they are still below the marker.
  final DateTime? wokeAt;
  final bool onTime;
  final int streak;
  final bool isMe;
  final CrewStatus status;

  /// The feed row this came from — null when the row was built from live
  /// status alone, in which case there is nothing to react to.
  final String? feedId;
  final List<FeedReaction> reactions;

  bool get isUp => wokeAt != null;

  /// The name to show: first name where there is one, else the handle.
  String get shortName {
    if (isMe) return 'You';
    if (displayName.isNotEmpty) return displayName.split(' ').first;
    return '@$username';
  }

  String get fullName {
    if (isMe) return 'You';
    return displayName.isNotEmpty ? displayName : '@$username';
  }

  /// What the row says about the wake. Deliberately never a judgement: the feed
  /// carries no scheduled time, so "woke up" is the honest phrasing for a wake
  /// that wasn't flagged on time — we do not invent a lateness.
  String get verdict {
    if (!isUp) return crewStatusLabel(status).toLowerCase();
    return onTime ? 'on time' : 'woke up';
  }

  CrewMember toMember() => CrewMember(
      id: id,
      username: username,
      displayName: displayName,
      avatarColor: avatarColor);
}

/// The assembled line: who is above the marker, who is below it, and the phase
/// that decides how it is drawn.
class MorningLine {
  const MorningLine({
    required this.phase,
    required this.up,
    required this.pending,
  });

  final MorningPhase phase;

  /// Everyone already up, ascending by wake time — the timeline reads downward
  /// toward the marker, so the most recent wake sits closest to it.
  final List<MorningEntry> up;

  /// Everyone still to come, waking first (they need the cheer now), then
  /// awake-elsewhere, asleep and quiet.
  final List<MorningEntry> pending;

  int get total => up.length + pending.length;

  /// The earliest riser, or null when nobody is up.
  MorningEntry? get first => up.isEmpty ? null : up.first;

  /// Everyone who had no wake at all — only meaningful once the window closed.
  List<MorningEntry> get missed =>
      [for (final e in pending) if (!e.isUp) e];

  static const empty =
      MorningLine(phase: MorningPhase.window, up: [], pending: []);
}

DateTime _localDay(DateTime t) {
  final l = t.toLocal();
  return DateTime(l.year, l.month, l.day);
}

/// Builds the line for [now] from the crew, their live statuses and today's
/// feed.
///
/// Only feed items from today's LOCAL day count as up — yesterday's wakes are
/// history, not this morning. The signed-in user is included as a row (their
/// own feed item if they have one, else their live status) so the line is never
/// a list of other people: on an empty crew it still shows one real morning.
MorningLine buildMorningLine({
  required DateTime now,
  required List<CrewMember> friends,
  required Map<String, CrewStatus> statuses,
  required List<FeedItem> feed,
  String? myId,
  String? myUsername,
  String? myDisplayName,
  String? myAvatarColor,
  CrewStatus myStatus = CrewStatus.unknown,
}) {
  final today = _localDay(now);
  final todays = [
    for (final f in feed)
      if (_localDay(f.wokeAt).isAtSameMomentAs(today)) f
  ];
  // Newest wins if a user somehow has two rows for one day.
  final byUser = <String, FeedItem>{};
  for (final f in todays) {
    final cur = byUser[f.userId];
    if (cur == null || f.wokeAt.isAfter(cur.wokeAt)) byUser[f.userId] = f;
  }

  MorningEntry entryFor({
    required String id,
    required String username,
    required String displayName,
    required String avatarColor,
    required bool isMe,
  }) {
    final f = byUser[id];
    return MorningEntry(
      id: id,
      username: username,
      displayName: displayName,
      avatarColor: avatarColor,
      status: statuses[id] ?? (isMe ? myStatus : CrewStatus.unknown),
      wokeAt: f?.wokeAt,
      onTime: f?.onTime ?? false,
      streak: f?.streak ?? 0,
      isMe: isMe,
      feedId: f?.id,
      reactions: f?.reactions ?? const [],
    );
  }

  final entries = <MorningEntry>[
    if (myId != null)
      entryFor(
        id: myId,
        username: myUsername ?? '',
        displayName: myDisplayName ?? '',
        avatarColor: myAvatarColor ?? '#71717A',
        isMe: true,
      ),
    for (final m in friends)
      if (m.id != myId)
        entryFor(
          id: m.id,
          username: m.username,
          displayName: m.displayName,
          avatarColor: m.avatarColor,
          isMe: false,
        ),
  ];

  final up = [for (final e in entries) if (e.isUp) e]
    ..sort((a, b) {
      final byTime = a.wokeAt!.compareTo(b.wokeAt!);
      return byTime != 0 ? byTime : a.username.compareTo(b.username);
    });
  final pending = [for (final e in entries) if (!e.isUp) e]
    ..sort((a, b) {
      final ra = _statusRank(a.status), rb = _statusRank(b.status);
      if (ra != rb) return ra.compareTo(rb);
      return a.username.compareTo(b.username);
    });

  return MorningLine(
    phase: phaseFor(
      now: now,
      todayWakes: [for (final e in up) e.wokeAt!],
      statuses: [for (final e in entries) e.status],
    ),
    up: up,
    pending: pending,
  );
}

/// Sort order below the marker. Mirrors `crewStatusStyle`'s ranking but lives
/// here so the domain does not reach into presentation.
int _statusRank(CrewStatus s) => switch (s) {
      CrewStatus.waking => 0,
      CrewStatus.out => 1,
      CrewStatus.awake => 2,
      CrewStatus.asleep => 3,
      CrewStatus.unknown => 4,
    };
