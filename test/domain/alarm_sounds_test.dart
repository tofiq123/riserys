import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/alarm_sounds.dart';

void main() {
  test('catalog is non-empty and Default maps to the entity default asset', () {
    expect(kAlarmSounds, isNotEmpty);
    expect(kAlarmSounds.first.label, 'Default');
    expect(kAlarmSounds.first.asset, 'sounds/default_alarm.mp3');
  });

  test('label<->asset round-trips for every catalog entry', () {
    for (final s in kAlarmSounds) {
      expect(soundLabelFor(s.asset), s.label);
      expect(soundAssetFor(s.label), s.asset);
    }
  });

  test('unknown asset or label falls back to the first entry', () {
    expect(soundLabelFor('sounds/does_not_exist.mp3'), kAlarmSounds.first.label);
    expect(soundAssetFor('Nonexistent'), kAlarmSounds.first.asset);
  });
}
