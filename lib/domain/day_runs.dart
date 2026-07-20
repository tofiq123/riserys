/// Small, pure helpers for reasoning about runs of consecutive local calendar
/// days. Flutter-free and DST-safe: all day maths goes through UTC-reconstructed
/// midnights so a daylight-saving shift never makes two adjacent days look one
/// or two apart.
library;

/// Whole days from [a] to [b], counting by calendar date only (the time-of-day
/// components are ignored). Positive when [b] is after [a]. DST-safe.
int daysBetween(DateTime a, DateTime b) {
  final ua = DateTime.utc(a.year, a.month, a.day);
  final ub = DateTime.utc(b.year, b.month, b.day);
  return ub.difference(ua).inDays;
}

/// The length of the longest run of consecutive calendar days present in
/// [days]. Duplicate days collapse to one; order does not matter. Returns 0 for
/// an empty input, 1 for isolated days with no neighbours.
int longestConsecutiveRun(Iterable<DateTime> days) {
  final unique = <DateTime>{
    for (final d in days) DateTime(d.year, d.month, d.day),
  }.toList()
    ..sort();
  if (unique.isEmpty) return 0;
  var best = 1;
  var run = 1;
  for (var i = 1; i < unique.length; i++) {
    if (daysBetween(unique[i - 1], unique[i]) == 1) {
      run++;
    } else {
      run = 1;
    }
    if (run > best) best = run;
  }
  return best;
}
