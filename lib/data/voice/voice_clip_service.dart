import '../../domain/voice_clip.dart';
import '../../domain/voice_recording.dart';

/// Send / receive / manage voice clips, abstracted so the send + inbox flows are
/// testable without a backend. Production is `SupabaseVoiceClipService`; tests
/// use [FakeVoiceClipService]; unconfigured/signed-out uses
/// [DisabledVoiceClipService].
abstract interface class VoiceClipService {
  /// Uploads [recording] to Storage, records a `voice_clips` row addressed to
  /// [targetId], and best-effort notifies them via the existing nudge/push path.
  /// Throws [VoiceClipException] with a user-facing message on failure.
  Future<void> send({
    required String targetId,
    required VoiceRecording recording,
  });

  /// Clips addressed to me, newest first. Empty when signed out/unconfigured.
  Future<List<VoiceClip>> inbox();

  /// A short-lived URL to stream/download [clip]'s audio for playback.
  Future<String> urlFor(VoiceClip clip);

  /// Marks a received clip as played (best-effort, one-way).
  Future<void> markPlayed(String clipId);

  /// Deletes a clip: its bytes (if I'm the sender) and my metadata row.
  Future<void> delete(VoiceClip clip);
}

/// A voice-clip action failed; [message] is user-facing.
class VoiceClipException implements Exception {
  const VoiceClipException(this.message);
  final String message;
  @override
  String toString() => 'VoiceClipException: $message';
}

/// In-memory [VoiceClipService] for unit/widget tests. Seed [inbox]; assertions
/// read [sent] / [markedPlayed] / [deleted].
class FakeVoiceClipService implements VoiceClipService {
  FakeVoiceClipService({
    List<VoiceClip> inbox = const [],
    this.failSendWith,
    this.signedUrl = 'https://fake.local/voice/clip.m4a',
  }) : _inbox = [...inbox];

  final List<VoiceClip> _inbox;

  /// When set, [send] throws a [VoiceClipException] with this message.
  final String? failSendWith;
  final String signedUrl;

  final List<({String targetId, VoiceRecording recording})> sent = [];
  final List<String> markedPlayed = [];
  final List<String> deleted = [];

  @override
  Future<void> send({
    required String targetId,
    required VoiceRecording recording,
  }) async {
    if (failSendWith != null) throw VoiceClipException(failSendWith!);
    sent.add((targetId: targetId, recording: recording));
  }

  @override
  Future<List<VoiceClip>> inbox() async => List.unmodifiable(_inbox);

  @override
  Future<String> urlFor(VoiceClip clip) async => signedUrl;

  @override
  Future<void> markPlayed(String clipId) async {
    markedPlayed.add(clipId);
    final i = _inbox.indexWhere((c) => c.id == clipId);
    if (i != -1 && !_inbox[i].isPlayed) {
      _inbox[i] = _inbox[i].copyWith(playedAt: DateTime.now());
    }
  }

  @override
  Future<void> delete(VoiceClip clip) async {
    deleted.add(clip.id);
    _inbox.removeWhere((c) => c.id == clip.id);
  }
}

/// Used when unconfigured/signed-out: an empty inbox; sending throws.
class DisabledVoiceClipService implements VoiceClipService {
  const DisabledVoiceClipService();

  @override
  Future<void> send({
    required String targetId,
    required VoiceRecording recording,
  }) async =>
      throw StateError('voice clips not configured');

  @override
  Future<List<VoiceClip>> inbox() async => const [];

  @override
  Future<String> urlFor(VoiceClip clip) async =>
      throw StateError('voice clips not configured');

  @override
  Future<void> markPlayed(String clipId) async {}

  @override
  Future<void> delete(VoiceClip clip) async {}
}
