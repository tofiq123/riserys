import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/consistency.dart';
import 'package:rise/domain/wake_event.dart';

/// A completed wake-up dismissed at [h]:[m] local on 2026-03-[day].
WakeEvent at(int day, int h, int m, {int id = 0}) {
  final ring = DateTime(2026, 3, day, 6);
  return WakeEvent(
    id: id,
    alarmId: 1,
    scheduledAt: ring,
    firstRingAt: ring,
    dismissedAt: DateTime(2026, 3, day, h, m),
    onTime: true,
  );
}

WakeEvent open(int day) {
  final ring = DateTime(2026, 3, day, 6);
  return WakeEvent(
      id: day, alarmId: 1, scheduledAt: ring, firstRingAt: ring, onTime: false);
}

void main() {
  test('null below the minimum event count', () {
    final events = [for (var d = 1; d <= 4; d++) at(d, 7, 0, id: d)];
    expect(consistencyScore(events), isNull);
  });

  test('open events do not count toward the gate', () {
    final events = [
      for (var d = 1; d <= 4; d++) at(d, 7, 0, id: d),
      open(5),
    ];
    expect(consistencyScore(events), isNull);
  });

  test('identical wake times score a perfect 100', () {
    final events = [for (var d = 1; d <= 6; d++) at(d, 7, 0, id: d)];
    expect(consistencyScore(events), 100);
  });

  test('a wide spread scores lower than a tight one', () {
    final tight = [
      for (var d = 1; d <= 6; d++) at(d, 7, d, id: d), // 7:01..7:06
    ];
    final wide = [
      at(1, 6, 0),
      at(2, 8, 0),
      at(3, 6, 30),
      at(4, 7, 45),
      at(5, 9, 0),
      at(6, 5, 30),
    ];
    final tightScore = consistencyScore(tight)!;
    final wideScore = consistencyScore(wide)!;
    expect(tightScore, greaterThan(wideScore));
    expect(tightScore, greaterThan(90));
  });

  test('a very large spread clamps to 0, never negative', () {
    final events = [
      at(1, 3, 0),
      at(2, 11, 0),
      at(3, 4, 0),
      at(4, 12, 0),
      at(5, 2, 0),
      at(6, 10, 0),
    ];
    final score = consistencyScore(events)!;
    expect(score, inInclusiveRange(0, 100));
    expect(score, lessThan(20));
  });

  test('band descriptors are neutral and threshold-correct', () {
    expect(consistencyBand(100), 'very steady');
    expect(consistencyBand(80), 'very steady');
    expect(consistencyBand(79), 'steady');
    expect(consistencyBand(60), 'steady');
    expect(consistencyBand(40), 'finding a rhythm');
    expect(consistencyBand(39), 'variable');
    expect(consistencyBand(0), 'variable');
  });
}
