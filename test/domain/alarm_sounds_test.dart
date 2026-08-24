import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/alarm_sounds.dart';

void main() {
  // The iOS alarm shipped silent because the tone library existed only in the
  // Android formats: iOS cannot decode .ogg for a notification sound, and a
  // notification whose sound name does not resolve to a bundled file is
  // delivered with NO sound at all. Every catalog tone therefore needs an iOS
  // twin in both formats, and a tone added to the catalog without one puts the
  // bug straight back. These two tests are that guard.
  group('every catalog tone has its iOS counterparts', () {
    String stem(AlarmSound s) {
      final base = s.asset.split('/').last;
      final dot = base.lastIndexOf('.');
      return dot == -1 ? base : base.substring(0, dot);
    }

    test('a bundled .caf exists for the notification sound', () {
      final missing = kAlarmSounds
          .where((s) => !File('ios/Runner/Sounds/${stem(s)}.caf').existsSync())
          .map(stem)
          .toList();
      expect(missing, isEmpty,
          reason: 'these tones would ring silently on iOS: $missing');
    });

    test('a Flutter .m4a exists for the in-app ring player', () {
      final missing = kAlarmSounds
          .where((s) => !File('assets/sounds/${stem(s)}.m4a').existsSync())
          .map(stem)
          .toList();
      expect(missing, isEmpty,
          reason: 'the iOS ring screen could not play these: $missing');
    });
  });

  test('catalog is Default-first and Default maps to the entity default asset',
      () {
    expect(kAlarmSounds, isNotEmpty);
    expect(kAlarmSounds.first.label, 'Default');
    expect(kAlarmSounds.first.asset, 'sounds/default_alarm.mp3');
    expect(kAlarmSounds.first.categoryKey, kDefaultCategory.key);
    expect(identical(kAlarmSounds.first, kDefaultSound), isTrue);
  });

  test('ships Default + the full 58-tone categorized library', () {
    // 58 bundled tones plus the pinned Default entry.
    expect(kAlarmSounds.length, 59);
    expect(kAlarmSounds.where((s) => s.categoryKey != kDefaultCategory.key),
        hasLength(58));

    // Seven ordered categories with the expected labels.
    expect(kSoundCategories.map((c) => c.key).toList(), [
      'gentle',
      'melodic',
      'energetic',
      'intense',
      'nature',
      'classic',
      'brutal',
    ]);
    expect(kSoundCategories.map((c) => c.label).toList(), [
      'Gentle',
      'Melodic',
      'Energetic',
      'Intense',
      'Nature',
      'Classic',
      'Brutal',
    ]);

    // Every non-default tone points at a bundled ogg under sounds/rise_*.
    for (final s in kAlarmSounds.where((s) => s != kDefaultSound)) {
      expect(s.asset, startsWith('sounds/rise_'));
      expect(s.asset, endsWith('.ogg'));
    }
  });

  test('every catalog asset resolves to a category', () {
    for (final s in kAlarmSounds) {
      final cat = soundCategoryFor(s.asset);
      expect(cat, isNotNull, reason: '${s.label} has no category');
      expect(cat!.key, s.categoryKey);
    }
    // A non-catalog asset (voice clip) resolves to no category.
    expect(soundCategoryFor('/data/voice_alarms/abc.m4a'), isNull);
  });

  test('soundsInCategory returns each category in catalog order', () {
    // The full library is partitioned across the seven categories.
    var total = 0;
    for (final c in kSoundCategories) {
      final tones = soundsInCategory(c.key);
      expect(tones, isNotEmpty, reason: '${c.key} is empty');
      for (final t in tones) {
        expect(t.categoryKey, c.key);
      }
      total += tones.length;
    }
    expect(total, 58);
    // The Default pseudo-category yields exactly the pinned entry.
    expect(soundsInCategory(kDefaultCategory.key), [kDefaultSound]);
    expect(soundsInCategory('nonexistent'), isEmpty);
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
    expect(soundLabelFor('sounds/does_not_exist.ogg'), kAlarmSounds.first.label);
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
      expect(previewAssetKeyFor('sounds/rise_sunrise.ogg'),
          'assets/sounds/rise_sunrise.ogg');
      expect(previewAssetKeyFor('sounds/rise_meltdown.ogg'),
          'assets/sounds/rise_meltdown.ogg');
    });

    test('Default, file paths, and unknown assets have no bundled preview', () {
      expect(previewAssetKeyFor(kDefaultSound.asset), isNull); // Default
      expect(previewAssetKeyFor('/data/voice_alarms/abc.m4a'), isNull);
      expect(previewAssetKeyFor('sounds/not_a_real_tone.ogg'), isNull);
    });
  });
}
