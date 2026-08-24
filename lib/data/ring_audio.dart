import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// Plays the alarm tone from inside the app while the ring screen is up.
///
/// This exists for iOS only, and the asymmetry is deliberate. On Android the
/// native `AlarmService` owns the sound: it starts playing before Flutter is
/// even alive, so a Dart player there would double up on the same tone. iOS has
/// no equivalent — its alarm is a local notification, and a notification's sound
/// stops after ~30 s, obeys the ringer volume, and is silenced outright by the
/// hardware mute switch. Without this player an iPhone showing the ring screen
/// makes no noise at all.
///
/// The session is configured `playback`, which is what lets the tone sound
/// through the mute switch — the one route iOS gives a non-system app to be
/// heard on a silenced phone.
abstract interface class RingAudio {
  /// Starts looping [soundAsset]. Never throws: a ring screen that cannot play
  /// audio must still render its dismissal UI.
  Future<void> start(String soundAsset);

  /// Stops playback and releases the session. Safe to call when not playing.
  Future<void> stop();
}

/// The no-op used wherever the platform already owns the alarm sound (Android)
/// and in widget tests, which must never touch a real audio device.
class SilentRingAudio implements RingAudio {
  const SilentRingAudio();

  @override
  Future<void> start(String soundAsset) async {}

  @override
  Future<void> stop() async {}
}

/// Records calls instead of playing, for tests that assert the ring screen
/// starts and stops the tone.
class FakeRingAudio implements RingAudio {
  final List<String> started = [];
  int stopCount = 0;

  @override
  Future<void> start(String soundAsset) async => started.add(soundAsset);

  @override
  Future<void> stop() async => stopCount++;
}

/// The iOS in-app player, over `just_audio`.
class IosRingAudio implements RingAudio {
  IosRingAudio({AudioPlayer? player}) : _player = player ?? AudioPlayer();

  final AudioPlayer _player;
  bool _configured = false;

  /// The bundled tones are `.ogg`, which iOS cannot decode — a parallel `.m4a`
  /// set ships beside them for exactly this player. Android keeps reading the
  /// `.ogg` (see `AlarmService.setSelectedSource`), so the stored
  /// `Alarm.soundAsset` stays `.ogg` on both platforms and nothing has to be
  /// migrated.
  @visibleForTesting
  static String iosAssetFor(String soundAsset) {
    final dot = soundAsset.lastIndexOf('.');
    final stem = dot == -1 ? soundAsset : soundAsset.substring(0, dot);
    return 'assets/$stem.m4a';
  }

  static bool _isFile(String asset) =>
      asset.startsWith('/') || asset.startsWith('file://');

  @override
  Future<void> start(String soundAsset) async {
    try {
      if (!_configured) {
        final session = await AudioSession.instance;
        // `playback` is the category that ignores the mute switch. Do not
        // downgrade it to `ambient`/`soloAmbient` — that silently gives back
        // the exact bug this player exists to fix.
        await session.configure(const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playback,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.duckOthers,
          avAudioSessionMode: AVAudioSessionMode.defaultMode,
        ));
        await session.setActive(true);
        _configured = true;
      }

      await _load(soundAsset);
      await _player.setLoopMode(LoopMode.one);
      await _player.setVolume(1);
      unawaited(_player.play());
    } catch (e) {
      // An alarm that cannot play its tone still has to show a dismiss button,
      // so this is logged and swallowed rather than propagated.
      debugPrint('Riserys: in-app ring audio failed for "$soundAsset": $e');
    }
  }

  /// Loads the chosen tone, falling back to the default one if it will not
  /// load — a voice clip whose file was cleaned up, or a tone name with no
  /// `.m4a` beside it, must not leave the ring screen silent.
  Future<void> _load(String soundAsset) async {
    try {
      if (_isFile(soundAsset)) {
        final path = soundAsset.startsWith('file://')
            ? Uri.parse(soundAsset).toFilePath()
            : soundAsset;
        await _player.setFilePath(path);
      } else {
        await _player.setAsset(iosAssetFor(soundAsset));
      }
      return;
    } catch (e) {
      debugPrint('Riserys: ring tone "$soundAsset" unplayable ($e); '
          'falling back to the default tone');
    }
    await _player.setAsset('assets/sounds/default_alarm.m4a');
  }

  @override
  Future<void> stop() async {
    try {
      await _player.stop();
      if (_configured) {
        final session = await AudioSession.instance;
        // Hand the session back so the user's music can resume after dismissal.
        await session.setActive(false);
        _configured = false;
      }
    } catch (e) {
      debugPrint('Riserys: stopping ring audio failed: $e');
    }
  }
}

/// The production [RingAudio]: a real player on iOS, a no-op everywhere else.
///
/// Constructed lazily per ring screen rather than as a singleton so the audio
/// resources are released with the screen.
RingAudio defaultRingAudio() =>
    Platform.isIOS ? IosRingAudio() : const SilentRingAudio();
