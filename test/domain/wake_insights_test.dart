import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/wake_event.dart';
import 'package:rise/domain/wake_insights.dart';

/// A completed wake-up dismissed at [dismissed] (local), on time by default.
WakeEvent ev(DateTime dismissed, {bool onTime = true, int id = 0}) {
  final ring = DateTime(dismissed.year, dismissed.month, dismissed.day, 6);
  return WakeEvent(
    id: id,
    alarmId: 1,
    scheduledAt: ring,
    firstRingAt: ring,
    dismissedAt: dismissed,
    onTime: onTime,
  );
}

/// An open (never dismissed) event — should be ignored by insights.
WakeEvent open(DateTime day, {int id = 0}) {
  final ring = DateTime(day.year, day.month, day.day, 6);
  return WakeEvent(
      id: id, alarmId: 1, scheduledAt: ring, firstRingAt: ring, onTime: false);
}

WakeInsight? of(List<WakeInsight> xs, WakeInsightKind kind) {
  for (final i in xs) {
    if (i.kind == kind) return i;
  }
  return null;
}

void main() {
  test('stays quiet below the minimum event count', () {
    // Mon..Thu 2026-07-20..23, four completed wake-ups (< kMinInsightEvents).
    final events = [
      for (var d = 20; d <= 23; d++) ev(DateTime(2026, 7, d, 6, 30), id: d),
    ];
    expect(events, hasLength(4));
    expect(buildWakeInsights(events), isEmpty);
  });

  test('open (undismissed) events do not count toward the gate', () {
    final events = [
      for (var d = 20; d <= 23; d++) ev(DateTime(2026, 7, d, 6, 30), id: d),
      open(DateTime(2026, 7, 24), id: 24), // one open -> still only 4 completed
    ];
    expect(buildWakeInsights(events), isEmpty);
  });

  test('reports an honest on-time rate once there is enough data', () {
    // 5 completed, 4 on time -> 80%.
    final events = [
      ev(DateTime(2026, 7, 20, 6, 30), id: 1),
      ev(DateTime(2026, 7, 21, 6, 30), id: 2),
      ev(DateTime(2026, 7, 22, 6, 30), id: 3),
      ev(DateTime(2026, 7, 23, 6, 30), id: 4),
      ev(DateTime(2026, 7, 24, 6, 30), onTime: false, id: 5),
    ];
    final onTime = of(buildWakeInsights(events), WakeInsightKind.onTime);
    expect(onTime, isNotNull);
    expect(onTime!.text, 'You woke on time on 80% of your 5 recorded wake-ups.');
  });

  test('compares weekday vs weekend wake times with direction and rounding', () {
    // Weekdays (Mon/Tue/Wed) at 06:30; weekend (Sat/Sun) at 08:00.
    final events = [
      ev(DateTime(2026, 7, 20, 6, 30), id: 1), // Mon
      ev(DateTime(2026, 7, 21, 6, 30), id: 2), // Tue
      ev(DateTime(2026, 7, 22, 6, 30), id: 3), // Wed
      ev(DateTime(2026, 7, 25, 8, 0), id: 4), // Sat
      ev(DateTime(2026, 7, 26, 8, 0), id: 5), // Sun
    ];
    final ins = of(buildWakeInsights(events), WakeInsightKind.weekdayWeekend);
    expect(ins, isNotNull);
    expect(ins!.text,
        'You wake about 90 min earlier on weekdays than on weekends.');
  });

  test('says weekday/weekend are close when the gap is small', () {
    final events = [
      ev(DateTime(2026, 7, 20, 6, 30), id: 1), // Mon
      ev(DateTime(2026, 7, 21, 6, 35), id: 2), // Tue
      ev(DateTime(2026, 7, 22, 6, 30), id: 3), // Wed
      ev(DateTime(2026, 7, 25, 6, 40), id: 4), // Sat
      ev(DateTime(2026, 7, 26, 6, 35), id: 5), // Sun
    ];
    final ins = of(buildWakeInsights(events), WakeInsightKind.weekdayWeekend);
    expect(ins, isNotNull);
    expect(ins!.text, 'Your weekday and weekend wake times stay pretty close.');
  });

  test('names the steadiest weekday when a day has enough repeats', () {
    // Three Wednesdays with a tight spread; two Mondays (too few to qualify).
    final events = [
      ev(DateTime(2026, 7, 22, 7, 0), id: 1), // Wed
      ev(DateTime(2026, 7, 29, 7, 5), id: 2), // Wed
      ev(DateTime(2026, 8, 5, 7, 2), id: 3), // Wed
      ev(DateTime(2026, 7, 20, 6, 30), id: 4), // Mon
      ev(DateTime(2026, 7, 27, 7, 45), id: 5), // Mon
    ];
    final ins = of(buildWakeInsights(events), WakeInsightKind.consistentDay);
    expect(ins, isNotNull);
    expect(ins!.text, 'Your wake time is steadiest on Wednesdays.');
  });

  test('measures consistency against the steady wake-time anchor', () {
    // Goal 07:00; four of five mornings land within 30 min, one is far off.
    final events = [
      ev(DateTime(2026, 7, 20, 7, 0), id: 1),
      ev(DateTime(2026, 7, 21, 7, 10), id: 2),
      ev(DateTime(2026, 7, 22, 6, 45), id: 3),
      ev(DateTime(2026, 7, 23, 7, 20), id: 4),
      ev(DateTime(2026, 7, 24, 9, 0), id: 5), // far from goal
    ];
    final ins = of(
        buildWakeInsights(events, targetWakeHour: 7, targetWakeMinute: 0),
        WakeInsightKind.goal);
    expect(ins, isNotNull);
    expect(ins!.text,
        'You woke within 30 min of your 7:00 AM goal on 4 of 5 mornings.');
  });

  test('no goal insight when no anchor is set', () {
    final events = [
      for (var d = 20; d <= 24; d++) ev(DateTime(2026, 7, d, 7, 0), id: d),
    ];
    expect(of(buildWakeInsights(events), WakeInsightKind.goal), isNull);
    // But other insights still appear.
    expect(buildWakeInsights(events), isNotEmpty);
  });

  test('insight copy carries no diagnostic or shaming words', () {
    final events = [
      ev(DateTime(2026, 7, 20, 6, 30), id: 1),
      ev(DateTime(2026, 7, 21, 6, 30), id: 2),
      ev(DateTime(2026, 7, 22, 6, 30), id: 3),
      ev(DateTime(2026, 7, 25, 8, 0), id: 4),
      ev(DateTime(2026, 7, 26, 8, 0), onTime: false, id: 5),
    ];
    final blob = buildWakeInsights(events, targetWakeHour: 7, targetWakeMinute: 0)
        .map((i) => i.text.toLowerCase())
        .join(' ');
    for (final banned in ['abnormal', 'irregular', 'disorder', 'lazy', 'bad', 'poor', 'fail']) {
      expect(blob.contains(banned), isFalse, reason: 'contains "$banned"');
    }
  });
}
