import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/crew_status.dart';

void main() {
  final now = DateTime.utc(2026, 7, 18, 6, 0); // fixed clock

  test('open wake event -> waking (wins over everything)', () {
    expect(
      deriveStatus(
        now: now,
        hasOpenWakeEvent: true,
        nextAlarmAt: now.add(const Duration(hours: 8)),
        lastDismissedAt: now.subtract(const Duration(minutes: 1)),
      ),
      CrewStatus.waking,
    );
  });

  test('dismissed within 4h -> awake', () {
    expect(
      deriveStatus(
          now: now,
          hasOpenWakeEvent: false,
          lastDismissedAt: now.subtract(const Duration(hours: 1))),
      CrewStatus.awake,
    );
    expect(
      deriveStatus(
          now: now,
          hasOpenWakeEvent: false,
          lastDismissedAt: now.subtract(const Duration(hours: 3, minutes: 59))),
      CrewStatus.awake,
    );
  });

  test('dismissed just over 4h ago is no longer awake', () {
    // No upcoming alarm within the window -> unknown.
    expect(
      deriveStatus(
          now: now,
          hasOpenWakeEvent: false,
          lastDismissedAt: now.subtract(const Duration(hours: 4, minutes: 1))),
      CrewStatus.unknown,
    );
  });

  test('a future dismissal (clock skew) does not count as awake', () {
    expect(
      deriveStatus(
          now: now,
          hasOpenWakeEvent: false,
          lastDismissedAt: now.add(const Duration(hours: 1))),
      CrewStatus.unknown,
    );
  });

  test('morning alarm within 10h and quiet >= 8h -> asleep', () {
    expect(
      deriveStatus(
          now: now,
          hasOpenWakeEvent: false,
          nextAlarmAt: now.add(const Duration(hours: 8)),
          lastDismissedAt: now.subtract(const Duration(hours: 10))),
      CrewStatus.asleep,
    );
  });

  test('morning alarm within 10h but with no prior dismissal at all -> asleep', () {
    expect(
      deriveStatus(
          now: now,
          hasOpenWakeEvent: false,
          nextAlarmAt: now.add(const Duration(hours: 2))),
      CrewStatus.asleep,
    );
  });

  test('alarm within 10h but active recently (5h ago) -> unknown, not asleep', () {
    expect(
      deriveStatus(
          now: now,
          hasOpenWakeEvent: false,
          nextAlarmAt: now.add(const Duration(hours: 8)),
          lastDismissedAt: now.subtract(const Duration(hours: 5))),
      CrewStatus.unknown,
    );
  });

  test('next alarm beyond the 10h lookahead -> unknown', () {
    expect(
      deriveStatus(
          now: now,
          hasOpenWakeEvent: false,
          nextAlarmAt: now.add(const Duration(hours: 12))),
      CrewStatus.unknown,
    );
  });

  test('a next-alarm time in the past does not make you asleep', () {
    expect(
      deriveStatus(
          now: now,
          hasOpenWakeEvent: false,
          nextAlarmAt: now.subtract(const Duration(minutes: 5))),
      CrewStatus.unknown,
    );
  });

  test('no alarm and no activity -> unknown', () {
    expect(
      deriveStatus(now: now, hasOpenWakeEvent: false),
      CrewStatus.unknown,
    );
  });
}
