import 'clock_format.dart';
import 'wake_event.dart';

/// The minimum number of completed wake-ups before any insight is shown. Below
/// this, patterns aren't meaningful yet — so we stay quiet rather than guess.
const int kMinInsightEvents = 5;

/// What an insight is about — the UI maps this to an icon. The domain stays
/// Flutter-free.
enum WakeInsightKind { onTime, weekdayWeekend, consistentDay, goal }

/// One honest, plain-language observation about the user's wake pattern.
///
/// Copy is deliberately factual and non-judgemental — never "abnormal",
/// diagnostic, or shaming. An insight describes what happened; it never labels
/// the person.
class WakeInsight {
  const WakeInsight(this.kind, this.text);
  final WakeInsightKind kind;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is WakeInsight && other.kind == kind && other.text == text;

  @override
  int get hashCode => Object.hash(kind, text);

  @override
  String toString() => 'WakeInsight($kind, "$text")';
}

/// Local minute-of-day (0..1439) the user actually got up — the dismissal time.
/// Null for events never dismissed (an open ring or a miss).
int? wakeMinuteOfDay(WakeEvent e) {
  final d = e.dismissedAt;
  if (d == null) return null;
  final l = d.toLocal();
  return l.hour * 60 + l.minute;
}

/// Builds the honest wake-pattern insights from the [events] log, using the
/// optional steady wake-time anchor ([targetWakeHour]/[targetWakeMinute]) when
/// set. Returns an empty list until there are at least [kMinInsightEvents]
/// completed wake-ups; each individual insight has its own data gate on top.
///
/// Pure and deterministic. Wake times are averaged naively as minute-of-day,
/// which is fine for a morning-alarm app (no wrap around midnight in practice).
List<WakeInsight> buildWakeInsights(
  List<WakeEvent> events, {
  int? targetWakeHour,
  int? targetWakeMinute,
  bool use24h = false,
}) {
  final dismissed = events.where((e) => e.dismissedAt != null).toList();
  if (dismissed.length < kMinInsightEvents) return const [];

  final n = dismissed.length;
  final out = <WakeInsight>[];

  // 1. On-time rate — plain and non-judgemental.
  final onTime = dismissed.where((e) => e.onTime).length;
  final pct = (onTime / n * 100).round();
  out.add(WakeInsight(WakeInsightKind.onTime,
      'You woke on time on $pct% of your $n recorded wake-ups.'));

  // 2. Consistency against the steady wake-time anchor, when one is set.
  if (targetWakeHour != null && targetWakeMinute != null) {
    final anchor = targetWakeHour * 60 + targetWakeMinute;
    final within = dismissed
        .where((e) => _clockDiff(wakeMinuteOfDay(e)!, anchor) <= 30)
        .length;
    out.add(WakeInsight(
        WakeInsightKind.goal,
        'You woke within 30 min of your '
        '${formatClock(targetWakeHour, targetWakeMinute, use24h: use24h)} goal '
        'on $within of $n mornings.'));
  }

  // 3. Weekday vs weekend average wake time.
  final weekdayMins = <int>[];
  final weekendMins = <int>[];
  for (final e in dismissed) {
    final wd = e.dismissedAt!.toLocal().weekday; // 1=Mon..7=Sun
    final m = wakeMinuteOfDay(e)!;
    if (wd == DateTime.saturday || wd == DateTime.sunday) {
      weekendMins.add(m);
    } else {
      weekdayMins.add(m);
    }
  }
  if (weekdayMins.length >= 2 && weekendMins.length >= 2) {
    final wdAvg = _mean(weekdayMins);
    final weAvg = _mean(weekendMins);
    final diff = weAvg - wdAvg; // >0 => weekends later => weekdays earlier
    final absMin = diff.abs();
    if (absMin >= 15) {
      final dir = diff > 0 ? 'earlier' : 'later';
      out.add(WakeInsight(WakeInsightKind.weekdayWeekend,
          'You wake about ${_roundTo5(absMin)} min $dir on weekdays than on weekends.'));
    } else {
      out.add(const WakeInsight(WakeInsightKind.weekdayWeekend,
          'Your weekday and weekend wake times stay pretty close.'));
    }
  }

  // 4. Steadiest day of the week (smallest spread), given enough repeats.
  final byWeekday = <int, List<int>>{};
  for (final e in dismissed) {
    byWeekday
        .putIfAbsent(e.dismissedAt!.toLocal().weekday, () => <int>[])
        .add(wakeMinuteOfDay(e)!);
  }
  int? steadiest;
  int? steadiestSpread;
  byWeekday.forEach((wd, mins) {
    if (mins.length < 3) return;
    final spread = mins.reduce((a, b) => a > b ? a : b) -
        mins.reduce((a, b) => a < b ? a : b);
    if (steadiestSpread == null ||
        spread < steadiestSpread! ||
        (spread == steadiestSpread! && wd < steadiest!)) {
      steadiest = wd;
      steadiestSpread = spread;
    }
  });
  if (steadiest != null) {
    out.add(WakeInsight(WakeInsightKind.consistentDay,
        'Your wake time is steadiest on ${_weekdayName(steadiest!)}s.'));
  }

  return out;
}

int _mean(List<int> xs) => (xs.reduce((a, b) => a + b) / xs.length).round();

int _roundTo5(int m) => (m / 5).round() * 5;

/// Shortest distance in minutes between two clock times on a 24-hour dial.
int _clockDiff(int a, int b) {
  final d = (a - b).abs() % 1440;
  return d > 720 ? 1440 - d : d;
}

const List<String> _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String _weekdayName(int weekday) => _weekdayNames[(weekday - 1) % 7];
