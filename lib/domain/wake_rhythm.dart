import 'dart:math' as math;

import 'wake_event.dart';

/// What one morning did, as a class the UI can draw as a *shape*.
///
/// Deliberately not a score: these five map one-to-one onto the mark vocabulary
/// (filled dot / hollow ring / cross / dash / nothing-yet). On-time green and
/// slept-through red are only ~5 ΔE apart under deuteranopia, so colour can
/// never be the only encoding — see `outcome_mark.dart`.
enum RhythmOutcome {
  /// Dismissed within [kOnTimeGrace] of the first ring.
  onTime,

  /// Woke, but outside the window. Never coloured as a failure.
  late,

  /// The alarm rang on a past day and was never dismissed.
  sleptThrough,

  /// The user marked it a rough night. Holds the streak; advances nothing.
  restDay,

  /// No alarm rang that day. Not a miss — simply nothing to say.
  noAlarm,

  /// Today's alarm rang and hasn't been finished yet. Undecided, not late.
  pending,
}

/// One morning on the rhythm chart.
///
/// Minutes are counted from the local midnight of [day], so a dismissal that
/// lands after midnight (a 23:55 alarm finished at 00:10) reads as 1450 rather
/// than wrapping to 10 and plotting upside down.
class RhythmDay {
  const RhythmDay({
    required this.day,
    required this.outcome,
    this.ringMinute,
    this.wokeMinute,
    this.graceMinutes = 15,
    this.freezeAbsorbed = false,
  });

  /// Local midnight of the morning this describes.
  final DateTime day;

  /// When the alarm first rang, or null when none did.
  final int? ringMinute;

  /// When it was dismissed, or null when it never was.
  final int? wokeMinute;

  final RhythmOutcome outcome;

  /// The on-time window's length, carried so the chart never hard-codes it.
  final int graceMinutes;

  /// A miss a banked freeze covered. Orthogonal to [outcome]: the morning is
  /// still honestly late or slept-through; this only explains why the run held.
  final bool freezeAbsorbed;

  bool get hasAlarm => ringMinute != null;

  /// The top of the on-time band — dismissing at or before this was on time.
  int? get graceEndMinute =>
      ringMinute == null ? null : ringMinute! + graceMinutes;

  /// Minutes past the window, or null when there is nothing to be late for.
  int? get lateBy {
    final end = graceEndMinute, woke = wokeMinute;
    if (end == null || woke == null || woke <= end) return null;
    return woke - end;
  }

  @override
  String toString() => 'RhythmDay(${day.toIso8601String().split("T").first}, '
      '$outcome, ring: $ringMinute, woke: $wokeMinute'
      '${freezeAbsorbed ? ", freeze" : ""})';
}

DateTime _midnight(DateTime t) {
  final l = t.toLocal();
  return DateTime(l.year, l.month, l.day);
}

int _minuteOfDay(DateTime t) {
  final l = t.toLocal();
  return l.hour * 60 + l.minute;
}

/// The representative event for each local day: the on-time one if the day had
/// several, else the latest ring. Mirrors the streak engine's "any on-time event
/// makes the day a success" rule, so the chart and the streak never disagree.
Map<DateTime, WakeEvent> _representatives(List<WakeEvent> events) {
  final byDay = <DateTime, WakeEvent>{};
  for (final e in events) {
    final d = e.localDay;
    final cur = byDay[d];
    final better = cur == null ||
        (e.onTime && !cur.onTime) ||
        (e.onTime == cur.onTime && e.firstRingAt.isAfter(cur.firstRingAt));
    if (better) byDay[d] = e;
  }
  return byDay;
}

RhythmDay _dayFor(
  DateTime day,
  DateTime today,
  Map<DateTime, WakeEvent> byDay,
  Set<DateTime> excusedDays,
  Set<DateTime> freezeAbsorbed,
) {
  final grace = kOnTimeGrace.inMinutes;
  final e = byDay[day];
  final absorbed = freezeAbsorbed.contains(day);

  if (e == null) {
    // An excused day with no alarm has nothing to excuse — it reads as a quiet
    // day, not as a rest day the user "used".
    return RhythmDay(
        day: day, outcome: RhythmOutcome.noAlarm, graceMinutes: grace);
  }

  final ring = _minuteOfDay(e.firstRingAt);
  int? woke;
  if (e.dismissedAt != null) {
    woke = _minuteOfDay(e.dismissedAt!);
    // Crossed midnight: keep counting up from this day's midnight.
    if (woke < ring) woke += 1440;
  }

  RhythmOutcome outcome;
  if (excusedDays.contains(day)) {
    outcome = RhythmOutcome.restDay;
  } else if (e.dismissedAt == null) {
    outcome = day.isAtSameMomentAs(today)
        ? RhythmOutcome.pending
        : RhythmOutcome.sleptThrough;
  } else if (e.onTime) {
    outcome = RhythmOutcome.onTime;
  } else {
    outcome = RhythmOutcome.late;
  }

  return RhythmDay(
    day: day,
    outcome: outcome,
    ringMinute: ring,
    wokeMinute: woke,
    graceMinutes: grace,
    freezeAbsorbed: absorbed,
  );
}

/// The last [days] local days, oldest first, ending today.
List<RhythmDay> buildRhythm(
  List<WakeEvent> events,
  DateTime now, {
  int days = 14,
  Set<DateTime> excusedDays = const {},
  Set<DateTime> freezeAbsorbed = const {},
}) {
  final today = _midnight(now);
  final byDay = _representatives(events);
  return [
    for (var i = days - 1; i >= 0; i--)
      _dayFor(today.subtract(Duration(days: i)), today, byDay, excusedDays,
          freezeAbsorbed),
  ];
}

/// Whole calendar weeks for the consistency grid: starts on the Monday of the
/// week [weeks] - 1 back, ends today. Because it always starts on a Monday the
/// grid needs no leading blanks, and the last row is simply short.
List<RhythmDay> buildRhythmWeeks(
  List<WakeEvent> events,
  DateTime now, {
  int weeks = 5,
  Set<DateTime> excusedDays = const {},
  Set<DateTime> freezeAbsorbed = const {},
}) {
  final today = _midnight(now);
  final thisMonday = today.subtract(Duration(days: today.weekday - 1));
  final start = thisMonday.subtract(Duration(days: (weeks - 1) * 7));
  final count = today.difference(start).inDays + 1;
  final byDay = _representatives(events);
  return [
    for (var i = 0; i < count; i++)
      _dayFor(start.add(Duration(days: i)), today, byDay, excusedDays,
          freezeAbsorbed),
  ];
}

/// The clock range the chart should plot, in minutes after local midnight.
///
/// Covers every ring, window top and wake in [days]; pads them; then widens to
/// [_minSpan] so a fortnight of near-identical mornings doesn't fill the plot
/// with noise. Snapped to quarter hours so the axis labels land on round times.
({int lo, int hi}) rhythmRange(List<RhythmDay> days) {
  const pad = 12, minSpan = 90;
  final vals = <int>[];
  for (final d in days) {
    final ring = d.ringMinute, end = d.graceEndMinute, woke = d.wokeMinute;
    if (ring != null) vals.add(ring);
    if (end != null) vals.add(end);
    if (woke != null) vals.add(woke);
  }
  // No mornings at all: a plain 05:00–09:00 morning, so the axis still reads.
  if (vals.isEmpty) return (lo: 5 * 60, hi: 9 * 60);

  var lo = vals.reduce(math.min) - pad;
  var hi = vals.reduce(math.max) + pad;
  if (hi - lo < minSpan) {
    final mid = (hi + lo) ~/ 2;
    lo = mid - minSpan ~/ 2;
    hi = mid + minSpan ~/ 2;
  }
  lo = (lo ~/ 15) * 15;
  hi = ((hi + 14) ~/ 15) * 15;
  return (lo: math.max(0, lo), hi: hi);
}

/// Days that had an alarm and a settled outcome — the denominator for anything
/// the chart claims. Rest days, quiet days and today's unfinished alarm are all
/// excluded: none of them is a morning you either hit or missed.
List<RhythmDay> settledDays(List<RhythmDay> days) => [
      for (final d in days)
        if (d.outcome != RhythmOutcome.noAlarm &&
            d.outcome != RhythmOutcome.restDay &&
            d.outcome != RhythmOutcome.pending)
          d
    ];

/// One honest sentence under the chart.
String rhythmSummary(List<RhythmDay> days) {
  final settled = settledDays(days);
  if (settled.isEmpty) return 'No mornings logged in this window yet.';
  final onTime =
      settled.where((d) => d.outcome == RhythmOutcome.onTime).length;
  final grace = settled.first.graceMinutes;
  final noun = settled.length == 1 ? 'morning' : 'mornings';
  return 'Up within $grace minutes of your alarm on $onTime '
      'of ${settled.length} $noun.';
}

/// Per-outcome counts for the grid's caption.
({int onTime, int late, int slept, int rest, int none, int pending}) rhythmTally(
    List<RhythmDay> days) {
  var onTime = 0, late = 0, slept = 0, rest = 0, none = 0, pending = 0;
  for (final d in days) {
    switch (d.outcome) {
      case RhythmOutcome.onTime:
        onTime++;
      case RhythmOutcome.late:
        late++;
      case RhythmOutcome.sleptThrough:
        slept++;
      case RhythmOutcome.restDay:
        rest++;
      case RhythmOutcome.noAlarm:
        none++;
      case RhythmOutcome.pending:
        pending++;
    }
  }
  return (
    onTime: onTime,
    late: late,
    slept: slept,
    rest: rest,
    none: none,
    pending: pending
  );
}

/// "24 on time · 2 late · 1 slept through · 3 rest days" — only the non-zero
/// parts, so a clean month doesn't read as a list of things that didn't happen.
String rhythmTallyLine(List<RhythmDay> days) {
  final t = rhythmTally(days);
  final parts = <String>[
    if (t.onTime > 0) '${t.onTime} on time',
    if (t.late > 0) '${t.late} late',
    if (t.slept > 0) '${t.slept} slept through',
    if (t.rest > 0) '${t.rest} rest ${t.rest == 1 ? "day" : "days"}',
  ];
  if (parts.isEmpty) return 'Nothing logged in these weeks yet.';
  return parts.join(' · ');
}
