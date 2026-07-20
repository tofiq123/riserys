import 'day_runs.dart';
import 'streak.dart';
import 'wake_event.dart';
import 'wake_insights.dart' show wakeMinuteOfDay;

/// Local hour before which a wake-up counts toward the "Early bird" badge.
const int kEarlyBirdHour = 6;

/// How many early wake-ups "Early bird" asks for.
const int kEarlyBirdTarget = 5;

/// Alertness score that earns "Sharp".
const int kSharpAlertness = 80;

/// Consecutive-day run length behind the weekly badges.
const int kWeekRun = 7;

/// One earned-or-locked badge. Badges celebrate a thing you *did* — never a
/// label about who you are. [title] names the accomplishment; [description]
/// states the action plainly. A locked badge is a goal to reach, never a
/// failure — the UI renders it as such.
///
/// [progress]/[target] describe how close a badge is when that reads naturally
/// (a streak-days or a count), and are null for binary badges. [target] is the
/// bar's full value; [progress] is where you are along it.
class Achievement {
  const Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.earned,
    this.progress,
    this.target,
  });

  final String id;
  final String title;
  final String description;
  final bool earned;
  final int? progress;
  final int? target;

  /// 0..1 completion toward [target], or null when a badge has no meaningful
  /// progress bar.
  double? get fraction {
    final t = target;
    final p = progress;
    if (t == null || p == null || t <= 0) return null;
    return (p / t).clamp(0.0, 1.0);
  }

  @override
  bool operator ==(Object other) =>
      other is Achievement &&
      other.id == id &&
      other.title == title &&
      other.description == description &&
      other.earned == earned &&
      other.progress == progress &&
      other.target == target;

  @override
  int get hashCode =>
      Object.hash(id, title, description, earned, progress, target);

  @override
  String toString() =>
      'Achievement($id, earned: $earned, progress: $progress/$target)';
}

/// Computes the full badge set from the wake log and the derived [streak],
/// each flagged earned or locked (with progress where natural). Pure and
/// deterministic; the returned order is stable for a stable display.
///
/// Streak badges read from [StreakStats.best] so a badge earned once is never
/// un-earned by a later miss — you *did* the seven days. The weekly-run badges
/// ("Perfect week", "No-snooze week") look for seven consecutive calendar days
/// meeting their bar anywhere in the log.
List<Achievement> earnedAchievements({
  required StreakStats streak,
  required List<WakeEvent> events,
}) {
  final dismissed = [for (final e in events) if (e.dismissedAt != null) e];

  // On-time calendar days (any on-time event that day).
  final onTimeDays = <DateTime>{
    for (final e in dismissed)
      if (e.onTime) e.localDay,
  };
  final perfectRun = longestConsecutiveRun(onTimeDays);

  // No-snooze days: a completed day where every dismissed event was snooze-free.
  final dayHasDismissal = <DateTime, bool>{};
  final daySnoozed = <DateTime, bool>{};
  for (final e in dismissed) {
    final d = e.localDay;
    dayHasDismissal[d] = true;
    daySnoozed[d] = (daySnoozed[d] ?? false) || e.snoozeCount > 0;
  }
  final noSnoozeDays = <DateTime>{
    for (final d in dayHasDismissal.keys)
      if (!(daySnoozed[d] ?? false)) d,
  };
  final noSnoozeRun = longestConsecutiveRun(noSnoozeDays);

  // Early wake-ups (dismissed before the threshold hour, local).
  final earlyCount = dismissed
      .where((e) => wakeMinuteOfDay(e)! < kEarlyBirdHour * 60)
      .length;

  // Best alertness score on record, if any.
  int? bestAlertness;
  for (final e in dismissed) {
    final s = e.alertnessScore;
    if (s != null && (bestAlertness == null || s > bestAlertness)) {
      bestAlertness = s;
    }
  }

  Achievement streakBadge(String id, String title, int days) => Achievement(
        id: id,
        title: title,
        description: 'Woke on time $days days in a row.',
        earned: streak.best >= days,
        progress: streak.best.clamp(0, days),
        target: days,
      );

  return [
    Achievement(
      id: 'first_light',
      title: 'First light',
      description: 'Completed your first wake-up.',
      earned: dismissed.isNotEmpty,
      progress: dismissed.isEmpty ? 0 : 1,
      target: 1,
    ),
    streakBadge('streak_7', '7-day streak', 7),
    streakBadge('streak_30', '30-day streak', 30),
    streakBadge('streak_100', '100-day streak', 100),
    Achievement(
      id: 'perfect_week',
      title: 'Perfect week',
      description: 'Seven on-time mornings in a row.',
      earned: perfectRun >= kWeekRun,
      progress: perfectRun.clamp(0, kWeekRun),
      target: kWeekRun,
    ),
    Achievement(
      id: 'no_snooze_week',
      title: 'No-snooze week',
      description: 'Seven days straight without a snooze.',
      earned: noSnoozeRun >= kWeekRun,
      progress: noSnoozeRun.clamp(0, kWeekRun),
      target: kWeekRun,
    ),
    Achievement(
      id: 'early_bird',
      title: 'Early bird',
      description: 'Woke before 6 AM $kEarlyBirdTarget times.',
      earned: earlyCount >= kEarlyBirdTarget,
      progress: earlyCount.clamp(0, kEarlyBirdTarget),
      target: kEarlyBirdTarget,
    ),
    Achievement(
      id: 'sharp',
      title: 'Sharp',
      description: 'Scored $kSharpAlertness+ alertness at wake-up.',
      earned: bestAlertness != null && bestAlertness >= kSharpAlertness,
      progress: (bestAlertness ?? 0).clamp(0, kSharpAlertness),
      target: kSharpAlertness,
    ),
  ];
}
