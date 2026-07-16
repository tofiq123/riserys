import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/ui/components/day_chips.dart';
import 'package:rise/ui/components/rise_switch.dart';
import 'package:rise/ui/components/segmented.dart';
import 'package:rise/ui/components/sound_chips.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('RiseSwitch toggles', (t) async {
    var v = false;
    await t.pumpWidget(_wrap(StatefulBuilder(builder: (c, setState) {
      return RiseSwitch(value: v, onChanged: (nv) => setState(() => v = nv));
    })));
    await t.tap(find.byType(RiseSwitch));
    await t.pumpAndSettle();
    expect(v, isTrue);
  });

  testWidgets('SegmentedControl reports the tapped value', (t) async {
    String? picked;
    await t.pumpWidget(_wrap(SegmentedControl<String>(
      segments: const [(value: 'a', label: 'Easy'), (value: 'b', label: 'Hard')],
      selected: 'a',
      onChanged: (v) => picked = v,
    )));
    await t.tap(find.text('Hard'));
    expect(picked, 'b');
  });

  testWidgets('DayChips toggles a day by index', (t) async {
    int? toggled;
    await t.pumpWidget(_wrap(DayChips(days: const {1, 2, 3, 4, 5}, onToggle: (i) => toggled = i)));
    // 7 letters S M T W T F S; tap the first (Sunday, index 0)
    await t.tap(find.text('S').first);
    expect(toggled, 0);
  });

  test('repeatLabel names common patterns', () {
    expect(repeatLabel(const {}), 'Once');
    expect(repeatLabel(const {1, 2, 3, 4, 5}), 'Weekdays');
    expect(repeatLabel(const {0, 6}), 'Weekends');
    expect(repeatLabel(const {0, 1, 2, 3, 4, 5, 6}), 'Every day');
    expect(repeatLabel(const {1, 3}), 'Mon, Wed');
  });

  testWidgets('SoundChips reports selection', (t) async {
    String? picked;
    await t.pumpWidget(_wrap(SoundChips(
      sounds: const ['Sunrise', 'Chimes'],
      selected: 'Sunrise',
      onChanged: (s) => picked = s,
    )));
    await t.tap(find.text('Chimes'));
    expect(picked, 'Chimes');
  });
}
