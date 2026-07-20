import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../domain/voice_recording.dart';

/// The hard ceiling on a voice clip. The UI stops recording here, the recorder
/// caps the returned duration to it, and the service/DB clamp to it — three
/// layers so a clip can never exceed 30s no matter which one is bypassed.
const Duration kMaxVoiceClipDuration = Duration(seconds: 30);

/// A thin, injectable microphone recorder. Real capture is device-only and
/// cannot be exercised in a unit test, so production ([RecordVoiceRecorder])
/// hides the `record` plugin behind this interface and tests inject a
/// [FakeVoiceRecorder]. Only pure orchestration around it is tested.
abstract interface class VoiceRecorder {
  /// Whether microphone permission is granted (requesting it if needed).
  Future<bool> hasPermission();

  /// Begins recording to a fresh temp file. A no-op if already recording.
  Future<void> start();

  /// Stops recording and returns the clip (path + measured, capped duration),
  /// or null if nothing was captured.
  Future<VoiceRecording?> stop();

  /// Aborts an in-progress recording and discards the file.
  Future<void> cancel();

  /// True between [start] and a [stop] / [cancel].
  bool get isRecording;

  /// Releases native resources. Wire to the provider's `onDispose`.
  Future<void> dispose();
}

/// Production [VoiceRecorder] over the `record` plugin. Records mono AAC into an
/// `.m4a` temp file and measures length with a [Stopwatch] (the plugin's stop()
/// returns only the path). Build-verified only — the mic path runs on a device.
class RecordVoiceRecorder implements VoiceRecorder {
  RecordVoiceRecorder({AudioRecorder? recorder})
      : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  final Stopwatch _elapsed = Stopwatch();
  String? _path;
  bool _recording = false;

  @override
  bool get isRecording => _recording;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<void> start() async {
    if (_recording) return;
    final dir = await getTemporaryDirectory();
    final path =
        p.join(dir.path, 'voice_${DateTime.now().microsecondsSinceEpoch}.m4a');
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, numChannels: 1),
      path: path,
    );
    _path = path;
    _elapsed
      ..reset()
      ..start();
    _recording = true;
  }

  @override
  Future<VoiceRecording?> stop() async {
    if (!_recording) return null;
    _recording = false;
    _elapsed.stop();
    final path = await _recorder.stop() ?? _path;
    _path = null;
    if (path == null) return null;
    final elapsed = _elapsed.elapsed;
    final duration =
        elapsed > kMaxVoiceClipDuration ? kMaxVoiceClipDuration : elapsed;
    return VoiceRecording(path: path, duration: duration);
  }

  @override
  Future<void> cancel() async {
    if (!_recording) return;
    _recording = false;
    _elapsed.stop();
    _path = null;
    try {
      await _recorder.cancel();
    } catch (_) {
      // best-effort — a failed cancel just leaves a temp file the OS reclaims.
    }
  }

  @override
  Future<void> dispose() => _recorder.dispose();
}

/// In-memory [VoiceRecorder] for tests. [permission] gates [hasPermission];
/// [result] is returned by [stop]. Records call counts for assertions.
class FakeVoiceRecorder implements VoiceRecorder {
  FakeVoiceRecorder({
    this.permission = true,
    this.result = const VoiceRecording(
        path: '/tmp/fake_clip.m4a', duration: Duration(seconds: 3)),
  });

  bool permission;
  VoiceRecording? result;

  bool _recording = false;
  int startCount = 0;
  int stopCount = 0;
  int cancelCount = 0;

  @override
  bool get isRecording => _recording;

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<void> start() async {
    if (_recording) return;
    _recording = true;
    startCount++;
  }

  @override
  Future<VoiceRecording?> stop() async {
    if (!_recording) return null;
    _recording = false;
    stopCount++;
    return result;
  }

  @override
  Future<void> cancel() async {
    _recording = false;
    cancelCount++;
  }

  @override
  Future<void> dispose() async {}
}
