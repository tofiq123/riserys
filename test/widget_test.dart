// Basic smoke test for the throwaway ringing screen (lib/ui/dev_ring_page.dart).
//
// The stock template's counter test no longer applies: main.dart's real home
// screen (DevHomePage) depends on native platform channels and a configured
// AlarmSyncService, neither of which a plain widget test provides. DevRingPage
// has no such dependency in its build method, so it is what this smoke test
// exercises instead.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rise/ui/dev_ring_page.dart';

void main() {
  testWidgets('DevRingPage shows the ringing alarm id and a dismiss button',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: DevRingPage(alarmId: 7)));

    expect(find.text('Alarm 7 is ringing'), findsOneWidget);
    expect(find.text('Dismiss'), findsOneWidget);
  });
}
