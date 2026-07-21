import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/alarm_sounds.dart';

void main() {
  test('catalog is non-empty and Default maps to the entity default asset', () {
    expect(kAlarmSounds, isNotEmpty);
    expect(kAlarmSounds.first.label, 'Default');
    expect(kAlarmSounds.first.asset, 'sounds/default_alarm.mp3');
  });

  test('ships the full bundled ringtone library', () {
    final labels = kAlarmSounds.map((s) => s.label).toList();
    expect(
      labels,
      containsAll(
          ['Default', 'Sunrise', 'Aurora', 'Tide', 'Ascend', 'Kalimba', 'Pulse']),
    );
    // Every non-default tone points at a bundled wav under sounds/rise_*.
    for (final s in kAlarmSounds.skip(1)) {
      expect(s.asset, startsWith('sounds/rise_'));
      expect(s.asset, endsWith('.wav'));
    }
  });

  test('labels and assets are unique (no collision in the catalog)', () {
    expect(kAlarmSounds.map((s) => s.label).toSet().length, kAlarmSounds.length);
    expect(kAlarmSounds.map((s) => s.asset).toSet().length, kAlarmSounds.length);
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

  group('isFileSound (sound-asset -> is-file-path decision)', () {
    test('absolute unix path and file:// URI are file sounds', () {
      expect(isFileSound('/data/user/0/app/voice_alarms/abc.m4a'), isTrue);
      expect(isFileSound('file:///data/app/clip.m4a'), isTrue);
    });

    test('bundled tone assets are not file sounds', () {
      for (final s in kAlarmSounds) {
        expect(isFileSound(s.asset), isFalse);
      }
    });
  });

  group('previewAssetKeyFor', () {
    test('bundled tones preview from assets/sounds/', () {
      expect(previewAssetKeyFor('sounds/rise_sunrise.wav'),
          'assets/sounds/rise_sunrise.wav');
      expect(previewAssetKeyFor('sounds/rise_pulse.wav'),
          'assets/sounds/rise_pulse.wav');
    });

    test('Default, file paths, and unknown assets have no bundled preview', () {
      expect(previewAssetKeyFor(kAlarmSounds.first.asset), isNull); // Default
      expect(previewAssetKeyFor('/data/voice_alarms/abc.m4a'), isNull);
      expect(previewAssetKeyFor('sounds/not_a_real_tone.wav'), isNull);
    });
  });
}
