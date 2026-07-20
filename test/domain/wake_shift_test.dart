import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/wake_shift.dart';

({int hour, int minute}) shift(int fh, int fm, int gh, int gm,
        {int step = 15}) =>
    nextShiftedWakeTime(
        fromHour: fh,
        fromMinute: fm,
        goalHour: gh,
        goalMinute: gm,
        stepMinutes: step);

void main() {
  test('already at the goal returns the goal', () {
    expect(shift(6, 0, 6, 0), (hour: 6, minute: 0));
  });

  test('within one step lands exactly on the goal (no overshoot)', () {
    // 10 min earlier, 15-min step -> exactly the goal.
    expect(shift(6, 10, 6, 0), (hour: 6, minute: 0));
    // 10 min later -> exactly the goal.
    expect(shift(6, 0, 6, 10), (hour: 6, minute: 10));
  });

  test('a large earlier gap moves one step earlier', () {
    expect(shift(8, 0, 6, 0), (hour: 7, minute: 45));
  });

  test('a large later gap moves one step later', () {
    expect(shift(6, 0, 8, 0), (hour: 6, minute: 15));
  });

  test('takes the shorter arc across midnight (later)', () {
    // 23:50 -> 00:10 is 20 min forward; one 15-min step -> 00:05.
    expect(shift(23, 50, 0, 10), (hour: 0, minute: 5));
  });

  test('takes the shorter arc across midnight (earlier)', () {
    // 00:05 -> 23:50 is 15 min backward; within a step -> exactly 23:50.
    expect(shift(0, 5, 23, 50), (hour: 23, minute: 50));
  });

  test('honors a custom step size', () {
    expect(shift(8, 0, 6, 0, step: 30), (hour: 7, minute: 30));
    expect(shift(6, 0, 9, 0, step: 5), (hour: 6, minute: 5));
  });

  test('repeated application converges on the goal and stops', () {
    var t = (hour: 8, minute: 0);
    for (var i = 0; i < 20; i++) {
      t = nextShiftedWakeTime(
          fromHour: t.hour, fromMinute: t.minute, goalHour: 6, goalMinute: 0);
    }
    expect(t, (hour: 6, minute: 0));
    // Once at the goal it is a fixed point.
    expect(
        nextShiftedWakeTime(
            fromHour: 6, fromMinute: 0, goalHour: 6, goalMinute: 0),
        (hour: 6, minute: 0));
  });

  test('formatShift renders a 12-hour clock string', () {
    expect(formatShift(shift(8, 0, 6, 0)), '7:45 AM');
  });
}
