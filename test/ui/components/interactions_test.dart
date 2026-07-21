import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/ui/components/slide_to_wake.dart';
import 'package:rise/ui/components/time_dial.dart';
import 'package:rise/ui/components/toast.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

/// The 24-hour hour a [DialTime] represents (the dial always carries 12h+AM/PM).
int _to24(DialTime v) {
  final h = v.hour12 % 12;
  return v.isAm ? h : h + 12;
}

void main() {
  group('TimeDial', () {
    testWidgets('dragging the hour up increments it by ~7px/step', (t) async {
      DialTime v = (hour12: 6, minute: 30, isAm: true);
      await t.pumpWidget(_wrap(StatefulBuilder(
        builder: (c, s) => TimeDial(value: v, onChanged: (nv) => s(() => v = nv)),
      )));
      await t.drag(find.text('6'), const Offset(0, -21)); // 21px up = 3 steps
      await t.pump();
      expect(v.hour12, 9);
    });

    testWidgets('hour wraps 12 -> 1 when dragged past the top', (t) async {
      DialTime v = (hour12: 11, minute: 0, isAm: true);
      await t.pumpWidget(_wrap(StatefulBuilder(
        builder: (c, s) => TimeDial(value: v, onChanged: (nv) => s(() => v = nv)),
      )));
      await t.drag(find.text('11'), const Offset(0, -21)); // +3 -> 11,12,1 -> 2
      await t.pump();
      expect(v.hour12, 2);
    });

    testWidgets('AM/PM toggle reports the change', (t) async {
      DialTime v = (hour12: 6, minute: 30, isAm: true);
      await t.pumpWidget(_wrap(StatefulBuilder(
        builder: (c, s) => TimeDial(value: v, onChanged: (nv) => s(() => v = nv)),
      )));
      await t.tap(find.text('PM'));
      await t.pump();
      expect(v.isAm, isFalse);
    });

    testWidgets('24h mode shows a 0–23 hour and hides the AM/PM toggle',
        (t) async {
      DialTime v = (hour12: 6, minute: 30, isAm: false); // 18:30
      await t.pumpWidget(_wrap(StatefulBuilder(
        builder: (c, s) =>
            TimeDial(use24h: true, value: v, onChanged: (nv) => s(() => v = nv)),
      )));
      expect(find.text('18'), findsOneWidget); // zero-padded 24h hour
      expect(find.text('AM'), findsNothing);
      expect(find.text('PM'), findsNothing);
    });

    testWidgets('24h mode: dragging the hour up moves through 0–23', (t) async {
      DialTime v = (hour12: 8, minute: 0, isAm: false); // 20:00
      await t.pumpWidget(_wrap(StatefulBuilder(
        builder: (c, s) =>
            TimeDial(use24h: true, value: v, onChanged: (nv) => s(() => v = nv)),
      )));
      await t.drag(find.text('20'), const Offset(0, -21)); // +3 -> 23
      await t.pump();
      expect(_to24(v), 23);
    });

    testWidgets('24h mode: the hour wraps 23 -> 0', (t) async {
      DialTime v = (hour12: 11, minute: 0, isAm: false); // 23:00
      await t.pumpWidget(_wrap(StatefulBuilder(
        builder: (c, s) =>
            TimeDial(use24h: true, value: v, onChanged: (nv) => s(() => v = nv)),
      )));
      await t.drag(find.text('23'), const Offset(0, -7)); // +1 -> wraps to 0
      await t.pump();
      expect(_to24(v), 0); // midnight
    });
  });

  group('SlideToWake', () {
    testWidgets('sliding to the end fires onWake', (t) async {
      var woke = false;
      await t.pumpWidget(_wrap(SizedBox(width: 300, child: SlideToWake(onWake: () => woke = true))));
      await t.drag(find.byType(SlideToWake), const Offset(300, 0));
      expect(woke, isTrue);
    });

    testWidgets('a short slide snaps back and does not fire', (t) async {
      var woke = false;
      await t.pumpWidget(_wrap(SizedBox(width: 300, child: SlideToWake(onWake: () => woke = true))));
      await t.drag(find.byType(SlideToWake), const Offset(40, 0));
      await t.pumpAndSettle();
      expect(woke, isFalse);
    });

    testWidgets('fires mid-drag when the threshold is crossed, before release', (t) async {
      var woke = false;
      await t.pumpWidget(_wrap(SizedBox(width: 300, child: SlideToWake(onWake: () => woke = true))));
      final g = await t.startGesture(t.getCenter(find.byType(SlideToWake)));
      await g.moveBy(const Offset(300, 0)); // cross the threshold mid-drag
      expect(woke, isTrue, reason: 'must fire during the drag, not on release');
      await g.up();
    });
  });

  group('ToastHost', () {
    testWidgets('shows the message then hides it after ~2.7s', (t) async {
      var hidden = false;
      await t.pumpWidget(_wrap(SizedBox(
        width: 300, height: 300,
        child: ToastHost(message: 'Alarm set', onHide: () => hidden = true, child: const SizedBox()),
      )));
      await t.pump();
      expect(find.text('Alarm set'), findsOneWidget);
      await t.pump(const Duration(milliseconds: 1000));
      expect(hidden, isFalse, reason: 'must not hide before ~2.7s');
      await t.pump(const Duration(milliseconds: 1800));
      expect(hidden, isTrue);
    });
  });
}
