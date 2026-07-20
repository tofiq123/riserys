import 'crew_member.dart';

/// A voice clip you have RECEIVED: an inbox item, with the sender already
/// resolved to a [CrewMember] for display. Mirrors a `public.voice_clips` row
/// addressed to you (`target_id = me`), minus your own id.
class VoiceClip {
  const VoiceClip({
    required this.id,
    required this.sender,
    required this.storagePath,
    required this.durationMs,
    required this.createdAt,
    this.playedAt,
  });

  /// The clip row id (uuid).
  final String id;

  /// Who sent it (the row's `owner_id`, resolved from `profiles`).
  final CrewMember sender;

  /// Path of the audio object in the private `voice-clips` bucket.
  final String storagePath;

  final int durationMs;

  final DateTime createdAt;

  /// When the recipient first played it, or null if unplayed.
  final DateTime? playedAt;

  bool get isPlayed => playedAt != null;

  Duration get duration => Duration(milliseconds: durationMs);

  VoiceClip copyWith({DateTime? playedAt}) => VoiceClip(
        id: id,
        sender: sender,
        storagePath: storagePath,
        durationMs: durationMs,
        createdAt: createdAt,
        playedAt: playedAt ?? this.playedAt,
      );

  @override
  bool operator ==(Object other) =>
      other is VoiceClip &&
      other.id == id &&
      other.sender == sender &&
      other.storagePath == storagePath &&
      other.durationMs == durationMs &&
      other.createdAt == createdAt &&
      other.playedAt == playedAt;

  @override
  int get hashCode =>
      Object.hash(id, sender, storagePath, durationMs, createdAt, playedAt);

  @override
  String toString() =>
      'VoiceClip(id: $id, sender: ${sender.username}, durationMs: $durationMs, '
      'played: $isPlayed)';
}
