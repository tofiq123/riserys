import 'wake_event.dart';

/// Difficulty tiers, easiest to hardest. The adaptive nudge only ever steps
/// one rung up this ladder.
const List<String> _tiers = ['easy', 'medium', 'hard'];

/// How many recent mission wake-ups must all be clean before we nudge harder.
const int _breezeWindow = 3;

/// The effective mission difficulty for the next ring, given the user's
/// [recentEvents] history. Pure and deterministic — the only input beyond
/// [baseDiff] is the event log, and callers pass a stable snapshot of it.
///
/// When the user has been *breezing* through their mission — the last
/// [_breezeWindow] (>=3) mission-method dismissals were all on-time with zero
/// mission failures — the difficulty is bumped ONE tier (easy->medium->hard,
/// capped at hard). Otherwise [baseDiff] is returned unchanged.
///
/// This is only ever a suggestion of *harder*, never a lockout: it changes
/// which mission variant is shown, not whether completing it dismisses. An
/// unknown [baseDiff] (not one of the tiers) is returned as-is.
String adaptiveDifficulty(String baseDiff, List<WakeEvent> recentEvents) {
  final tier = _tiers.indexOf(baseDiff);
  // Unknown difficulty, or already at the hardest tier: nothing to bump.
  if (tier == -1 || tier == _tiers.length - 1) return baseDiff;

  // The finalized mission-method wake-ups, most recent first. A still-open ring
  // (dismissedAt == null) or a non-mission dismissal (slide/safety) is ignored.
  final missionWakes = recentEvents
      .where((e) => e.method == 'mission' && e.dismissedAt != null)
      .toList()
    ..sort((a, b) => b.firstRingAt.compareTo(a.firstRingAt));

  // Not enough evidence yet — keep the user's chosen difficulty.
  if (missionWakes.length < _breezeWindow) return baseDiff;

  final breezing = missionWakes
      .take(_breezeWindow)
      .every((e) => e.onTime && e.missionFailures == 0);

  return breezing ? _tiers[tier + 1] : baseDiff;
}
