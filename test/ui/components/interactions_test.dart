import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/ui/components/slide_to_wake.dart';
import 'package:rise/ui/components/time_dial.dart';
import 'package:rise/ui/components/toast.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

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
      await t.pump(const Duration(milliseconds: 2800));
      expect(hidden, isTrue);
    });
  });
}
