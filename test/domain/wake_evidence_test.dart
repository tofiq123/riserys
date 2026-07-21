import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/wake_event.dart';
import 'package:rise/domain/wake_evidence.dart';

WakeEvent _event({
  DateTime? scheduledAt,
  DateTime? dismissedAt,
  String? method,
  int snoozeCount = 0,
  int missionFailures = 0,
  bool onTime = false,
  int? alertnessScore,
}) {
  final sched = scheduledAt ?? DateTime.utc(2026, 7, 22, 6, 30);
  return WakeEvent(
    id: 1,
    alarmId: 1,
    scheduledAt: sched,
    firstRingAt: sched,
    dismissedAt: dismissedAt ?? sched.add(const Duration(minutes: 2)),
    method: method,
    snoozeCount: snoozeCount,
    missionFailures: missionFailures,
    onTime: onTime,
    alertnessScore: alertnessScore,
  );
}

void main() {
  test('no event or an open event yields no card', () {
    expect(WakeEvidence.of(null), isNull);
    final open = WakeEvent(
      id: 1,
      alarmId: 1,
      scheduledAt: DateTime.utc(2026, 7, 22, 6, 30),
      firstRingAt: DateTime.utc(2026, 7, 22, 6, 30),
    );
    expect(open.isOpen, isTrue);
    expect(WakeEvidence.of(open), isNull);
  });

  test('a clean wake-up scores high with a good verdict', () {
    final e = _event(
      method: 'mission',
      onTime: true,
      snoozeCount: 0,
      alertnessScore: 85,
    );
    final ev = WakeEvidence.of(e, leftHome: true)!;
    expect(ev.score, greaterThanOrEqualTo(80));
    expect(ev.verdict, 'Clean wake-up');
    expect(ev.tone, EvidenceTone.good);
    // Every contributing signal is present.
    expect(ev.signals.map((s) => s.label),
        containsAll(['On time', 'Left home', 'Mission', 'No snoozes', 'Alertness']));
  });

  test('a rough wake-up scores low but stays kind', () {
    final e = _event(
      method: 'safety',
      onTime: false,
      dismissedAt: DateTime.utc(2026, 7, 22, 7, 45), // 75 min late
      snoozeCount: 4,
    );
    final ev = WakeEvidence.of(e)!;
    expect(ev.score, lessThan(40));
    expect(ev.verdict, 'Rough morning');
    expect(ev.tone, EvidenceTone.bad);
    expect(ev.blurb, contains('fresh start')); // never shaming
    expect(ev.signals.firstWhere((s) => s.label == 'Woke late').detail,
        '1h 15m late');
  });

  test('left-home only ever helps the score, never present when absent', () {
    final base = _event(method: 'slide', onTime: true);
    final without = WakeEvidence.of(base, leftHome: false)!;
    final with_ = WakeEvidence.of(base, leftHome: true)!;
    expect(with_.score, greaterThan(without.score));
    expect(without.signals.any((s) => s.label == 'Left home'), isFalse);
    expect(with_.signals.any((s) => s.label == 'Left home'), isTrue);
  });

  test('alertness only appears when the PVT produced a score', () {
    expect(
      WakeEvidence.of(_event(onTime: true))!
          .signals
          .any((s) => s.label == 'Alertness'),
      isFalse,
    );
    final graded = WakeEvidence.of(_event(onTime: true, alertnessScore: 30))!;
    final alert = graded.signals.firstWhere((s) => s.label == 'Alertness');
    expect(alert.detail, '30/100');
    expect(alert.tone, EvidenceTone.bad);
  });

  test('signals are ordered most-reassuring first', () {
    final ev = WakeEvidence.of(
      _event(method: 'safety', onTime: true, snoozeCount: 2),
    )!;
    // 'On time' (good) must sort ahead of 'Safety dismiss' (bad).
    final onTimeIdx = ev.signals.indexWhere((s) => s.label == 'On time');
    final safetyIdx = ev.signals.indexWhere((s) => s.label == 'Safety dismiss');
    expect(onTimeIdx, lessThan(safetyIdx));
  });

  test('score is clamped into 0..100', () {
    // Pile on negatives; must not go below 0.
    final worst = _event(
      method: 'safety',
      onTime: false,
      dismissedAt: DateTime.utc(2026, 7, 22, 9, 0),
      snoozeCount: 9,
      missionFailures: 9,
      alertnessScore: 0,
    );
    final ev = WakeEvidence.of(worst)!;
    expect(ev.score, inInclusiveRange(0, 100));
  });
}
