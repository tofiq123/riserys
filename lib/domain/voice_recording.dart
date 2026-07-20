/// The result of a finished local recording: a file on disk plus its measured
/// (capped) length. Transient — it lives only between recording and upload; the
/// stored, sharable clip is a [VoiceClip].
class VoiceRecording {
  const VoiceRecording({required this.path, required this.duration});

  /// Absolute path to the recorded audio file (an .m4a in a temp directory).
  final String path;

  /// How long the clip runs, already clamped to the max clip length.
  final Duration duration;

  @override
  bool operator ==(Object other) =>
      other is VoiceRecording &&
      other.path == path &&
      other.duration == duration;

  @override
  int get hashCode => Object.hash(path, duration);

  @override
  String toString() => 'VoiceRecording(path: $path, duration: $duration)';
}
