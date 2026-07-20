import 'dart:async';

import 'package:just_audio/just_audio.dart';

/// A thin, injectable audio player for voice-clip previews + inbox playback.
/// Real playback is device-only, so production ([JustAudioVoicePlayer]) hides
/// the `just_audio` plugin behind this interface and tests inject a
/// [FakeVoicePlayer].
abstract interface class VoicePlayer {
  /// Plays audio from [source] — an https URL (a Storage signed URL) or a local
  /// file path. The future completes when playback finishes or is stopped.
  Future<void> play(String source);

  /// Stops playback.
  Future<void> stop();

  /// Emits true while audio is actively playing, false when stopped/finished.
  Stream<bool> get playingStream;

  /// Releases native resources. Wire to the provider's `onDispose`.
  Future<void> dispose();
}

/// Production [VoicePlayer] over `just_audio`. Build-verified only — audio
/// output runs on a device.
class JustAudioVoicePlayer implements VoicePlayer {
  JustAudioVoicePlayer({AudioPlayer? player})
      : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  @override
  Stream<bool> get playingStream => _player.playingStream;

  @override
  Future<void> play(String source) async {
    await _player.stop();
    if (source.startsWith('http')) {
      await _player.setUrl(source);
    } else {
      await _player.setFilePath(source);
    }
    // play() completes when playback reaches the end or is stopped. Stop after
    // so `playing` returns to false and a later play() replays from the start.
    await _player.play();
    await _player.stop();
  }

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}

/// In-memory [VoicePlayer] for tests. Records the last source + counts, and
/// completes [play] immediately unless [gate] is set (to test mid-play stop).
class FakeVoicePlayer implements VoicePlayer {
  final StreamController<bool> _playing = StreamController<bool>.broadcast();

  String? lastPlayed;
  int playCount = 0;
  int stopCount = 0;

  /// When set, [play] awaits this before completing, so a test can assert the
  /// "playing" state and then release it.
  Completer<void>? gate;

  @override
  Stream<bool> get playingStream => _playing.stream;

  @override
  Future<void> play(String source) async {
    lastPlayed = source;
    playCount++;
    _playing.add(true);
    final g = gate;
    if (g != null) await g.future;
    _playing.add(false);
  }

  @override
  Future<void> stop() async {
    stopCount++;
    _playing.add(false);
  }

  @override
  Future<void> dispose() async {
    await _playing.close();
  }
}
