import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/crew_member.dart';
import '../../domain/voice_clip.dart';
import '../../domain/voice_recording.dart';
import '../nudge/nudge_service.dart';
import 'voice_clip_service.dart';
import 'voice_recorder.dart' show kMaxVoiceClipDuration;

/// Production [VoiceClipService]: audio bytes in the private `voice-clips`
/// Storage bucket under `<owner>/<random>.m4a`, metadata in `public.voice_clips`
/// (RLS in migration 0007). Notifies the recipient via the existing
/// [NudgeService] push path (best-effort). Only constructed when configured.
///
/// NOTE: build-verified only (no live backend / Storage in CI). Exercised by the
/// two-account send/receive smoke test in the Phase 16 setup guide.
class SupabaseVoiceClipService implements VoiceClipService {
  SupabaseVoiceClipService({
    required NudgeService nudge,
    SupabaseClient? client,
  })  : _client = client ?? Supabase.instance.client,
        _nudge = nudge;

  static const _bucket = 'voice-clips';
  static const _defaultAvatarColor = '#7C9CF4';
  static final _rng = Random.secure();

  final SupabaseClient _client;
  final NudgeService _nudge;

  String _requireMe() {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw StateError('voice action while signed out');
    return id;
  }

  /// 128 bits of randomness as hex — the object filename (never the row id).
  String _randomId() {
    final bytes = List<int>.generate(16, (_) => _rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  CrewMember _memberFromProfile(Map<String, dynamic> p) => CrewMember(
        id: p['id'] as String,
        username: (p['username'] as String?) ?? '',
        displayName: (p['display_name'] as String?) ?? '',
        avatarColor: (p['avatar_color'] as String?) ?? _defaultAvatarColor,
      );

  @override
  Future<void> send({
    required String targetId,
    required VoiceRecording recording,
  }) async {
    final me = _requireMe();
    final path = '$me/${_randomId()}.m4a';

    // 1. Upload the bytes. Storage RLS permits writes only under our own prefix.
    try {
      final bytes = await File(recording.path).readAsBytes();
      await _client.storage.from(_bucket).uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
                contentType: 'audio/mp4', upsert: false),
          );
    } on StorageException catch (e) {
      throw VoiceClipException(_storageMessage(e));
    } on FileSystemException {
      throw const VoiceClipException("Couldn't read the recording. Try again.");
    }

    // 2. Insert the metadata row. The INSERT RLS policy re-checks friendship, so
    // a non-friend target is rejected here — roll back the orphaned object.
    final durationMs = recording.duration.inMilliseconds
        .clamp(0, kMaxVoiceClipDuration.inMilliseconds);
    try {
      await _client.from('voice_clips').insert({
        'owner_id': me,
        'target_id': targetId,
        'storage_path': path,
        'duration_ms': durationMs,
      });
    } on PostgrestException catch (e) {
      await _tryRemoveObject(path);
      // 42501 = RLS violation (not an accepted friend / not allowed).
      if (e.code == '42501' ||
          e.message.toLowerCase().contains('row-level security')) {
        throw const VoiceClipException('You can only send clips to your crew.');
      }
      throw const VoiceClipException("Couldn't send the clip. Try again.");
    }

    // 3. Notify via the existing nudge/push path, typed as a voice-clip push
    // ("new voice clip" copy; and the server lets it through the nudge
    // cooldown because the clip row we just inserted proves a real send).
    // Best-effort: a rate-limit or offline device must not fail an
    // already-stored clip.
    try {
      await _nudge.nudge(targetId, kind: NudgeKind.voice);
    } catch (_) {}
  }

  @override
  Future<List<VoiceClip>> inbox() async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return const [];

    final rows = await _client
        .from('voice_clips')
        .select('id, owner_id, storage_path, duration_ms, created_at, played_at')
        .eq('target_id', me)
        .order('created_at', ascending: false);

    if (rows.isEmpty) return const [];

    final ownerIds =
        <String>{for (final r in rows) r['owner_id'] as String}.toList();
    final profiles = await _client
        .from('profiles')
        .select('id, username, display_name, avatar_color')
        .inFilter('id', ownerIds);
    final byId = {
      for (final p in profiles) p['id'] as String: _memberFromProfile(p),
    };

    return rows.map((r) {
      final ownerId = r['owner_id'] as String;
      final sender = byId[ownerId] ??
          CrewMember(
              id: ownerId,
              username: '',
              displayName: '',
              avatarColor: _defaultAvatarColor);
      return VoiceClip(
        id: r['id'] as String,
        sender: sender,
        storagePath: r['storage_path'] as String,
        durationMs: (r['duration_ms'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse(r['created_at'] as String),
        playedAt: r['played_at'] == null
            ? null
            : DateTime.parse(r['played_at'] as String),
      );
    }).toList();
  }

  @override
  Future<String> urlFor(VoiceClip clip) =>
      _client.storage.from(_bucket).createSignedUrl(clip.storagePath, 3600);

  @override
  Future<String> downloadForAlarm(VoiceClip clip) async {
    try {
      // Persistent app storage (not the temp dir): the file must survive until
      // the alarm rings, possibly days later. Keyed by clip id so re-downloading
      // the same clip overwrites rather than piling up copies.
      final dir = await getApplicationDocumentsDirectory();
      final soundsDir = Directory(p.join(dir.path, 'voice_alarms'));
      if (!await soundsDir.exists()) {
        await soundsDir.create(recursive: true);
      }
      final dest = p.join(soundsDir.path, '${clip.id}.m4a');
      final bytes = await _client.storage.from(_bucket).download(clip.storagePath);
      await File(dest).writeAsBytes(bytes);
      return dest;
    } on StorageException {
      throw const VoiceClipException("Couldn't download that clip. Try again.");
    } on FileSystemException {
      throw const VoiceClipException("Couldn't save that clip to your phone.");
    }
  }

  @override
  Future<void> markPlayed(String clipId) async {
    final me = _requireMe();
    try {
      // Only stamp once — the write-once guard would otherwise raise. `isFilter`
      // skips already-played rows.
      await _client
          .from('voice_clips')
          .update({'played_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', clipId)
          .eq('target_id', me)
          .isFilter('played_at', null);
    } catch (_) {
      // Best-effort: marking-played must never block playback.
    }
  }

  @override
  Future<void> delete(VoiceClip clip) async {
    _requireMe();
    // Remove the bytes if I'm the owner; the recipient's remove() is denied by
    // Storage RLS, which we ignore — dropping the row is enough for them.
    await _tryRemoveObject(clip.storagePath);
    try {
      await _client.from('voice_clips').delete().eq('id', clip.id);
    } on PostgrestException {
      throw const VoiceClipException("Couldn't delete the clip. Try again.");
    }
  }

  Future<void> _tryRemoveObject(String path) async {
    try {
      await _client.storage.from(_bucket).remove([path]);
    } catch (_) {}
  }

  String _storageMessage(StorageException e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('exceeded') || msg.contains('size')) {
      return 'That clip is too long to send.';
    }
    return "Couldn't upload the clip. Try again.";
  }
}
