import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/supabase_config.dart';
import '../../data/voice/supabase_voice_clip_service.dart';
import '../../data/voice/voice_clip_service.dart';
import '../../data/voice/voice_player.dart';
import '../../data/voice/voice_recorder.dart';
import '../../domain/voice_clip.dart';
import 'auth_providers.dart';
import 'nudge_providers.dart';

/// The device microphone recorder. Real capture on device; tests override this
/// with a `FakeVoiceRecorder`.
final voiceRecorderProvider = Provider<VoiceRecorder>((ref) {
  final recorder = RecordVoiceRecorder();
  ref.onDispose(recorder.dispose);
  return recorder;
});

/// The audio player for previews + inbox playback. Tests override with a
/// `FakeVoicePlayer`.
final voicePlayerProvider = Provider<VoicePlayer>((ref) {
  final player = JustAudioVoicePlayer();
  ref.onDispose(player.dispose);
  return player;
});

/// The app's [VoiceClipService]. Configured → a real
/// [SupabaseVoiceClipService]; otherwise a [DisabledVoiceClipService] (empty
/// inbox, sending disabled). Tests override with a `FakeVoiceClipService`.
final voiceClipServiceProvider = Provider<VoiceClipService>((ref) {
  if (!SupabaseConfig.isConfigured) {
    return const DisabledVoiceClipService();
  }
  return SupabaseVoiceClipService(nudge: ref.watch(nudgeServiceProvider));
});

/// The signed-in user's received clips, newest first. Cached for the session
/// (keeps the Crew unread badge stable across tab switches); invalidate after
/// play/delete, on pull-to-refresh, or on tab open to refresh. Keyed to the
/// signed-in account id so cached clips never outlive their account.
final voiceInboxProvider = FutureProvider<List<VoiceClip>>((ref) {
  ref.watch(accountProvider.select((a) => a.value?.id));
  return ref.watch(voiceClipServiceProvider).inbox();
});
