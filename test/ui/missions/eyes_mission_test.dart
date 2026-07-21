import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/alarm.dart';
import 'package:rise/ui/missions/eyes_mission.dart';
import 'package:rise/ui/missions/mission_host.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  // The front-camera + ML Kit pipeline is a live platform integration that
  // cannot render/run headlessly, so — like the QR/steps/photo missions — only
  // the host dispatch is asserted here (never pumped: rendering would open the
  // camera). The sustained-open decision is covered by
  // test/domain/eye_open_test.dart. Device-verify the live detection.
  testWidgets('buildMission dispatches to EyesMission carrying the difficulty',
      (t) async {
    late BuildContext ctx;
    await t.pumpWidget(_wrap(Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    final w = buildMission(
      ctx,
      const Alarm(
          id: 1, hour: 6, minute: 0, mission: 'eyes', missionDiff: 'hard'),
      () {},
    );
    expect(w, isA<EyesMission>());
    expect((w as EyesMission).diff, 'hard');
  });
}
