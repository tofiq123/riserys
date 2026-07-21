import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/alarm.dart';
import 'package:rise/ui/missions/mission_host.dart';
import 'package:rise/ui/missions/photo_mission.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  // The camera preview is a live platform view that cannot render headlessly,
  // so — like the QR/steps missions — only the host dispatch and the reference
  // wiring are asserted here. The pass/fail logic is covered by
  // test/domain/photo_match_test.dart. Device-verify preview + capture.
  group('buildMission host (non-rendering: camera cannot render headlessly)', () {
    testWidgets('dispatches to PhotoMission carrying the registered hash',
        (t) async {
      late BuildContext ctx;
      await t.pumpWidget(_wrap(Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      })));
      final w = buildMission(
        ctx,
        const Alarm(
            id: 1,
            hour: 6,
            minute: 0,
            mission: 'photo',
            missionData: '0f0f0f0f0f0f0f0f'),
        () {},
      );
      expect(w, isA<PhotoMission>());
      expect((w as PhotoMission).reference, '0f0f0f0f0f0f0f0f');
    });

    testWidgets('an unconfigured photo alarm passes a null reference', (t) async {
      late BuildContext ctx;
      await t.pumpWidget(_wrap(Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      })));
      final w = buildMission(
          ctx, const Alarm(id: 1, hour: 6, minute: 0, mission: 'photo'), () {});
      expect((w as PhotoMission).reference, isNull);
    });
  });
}
