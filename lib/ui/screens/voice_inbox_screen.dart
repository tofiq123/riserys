import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/voice/voice_clip_service.dart';
import '../../domain/alarm.dart';
import '../../domain/voice_clip.dart';
import '../components/rise_card.dart';
import '../components/toast.dart';
import '../state/alarm_providers.dart';
import '../state/settings_providers.dart';
import '../state/voice_providers.dart';
import '../theme/avatar_color.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// The Voice inbox: clips a crew member has sent you, newest first. Play them,
/// and delete the ones you're done with. Playback goes through the injectable
/// player, so this is widget-testable with fakes.
class VoiceInboxScreen extends ConsumerStatefulWidget {
  const VoiceInboxScreen({super.key});

  @override
  ConsumerState<VoiceInboxScreen> createState() => _VoiceInboxScreenState();
}

class _VoiceInboxScreenState extends ConsumerState<VoiceInboxScreen> {
  String? _playingId;
  final Set<String> _busy = {};

  void _snack(String message, {RiseToastKind kind = RiseToastKind.info}) {
    if (!mounted) return;
    RiseToast.show(context, message, kind: kind);
  }

  Future<void> _play(VoiceClip clip) async {
    final player = ref.read(voicePlayerProvider);
    if (_playingId == clip.id) {
      await player.stop();
      if (mounted) setState(() => _playingId = null);
      return;
    }
    setState(() => _playingId = clip.id);
    final service = ref.read(voiceClipServiceProvider);
    try {
      final url = await service.urlFor(clip);
      await service.markPlayed(clip.id);
      await player.play(url);
    } catch (_) {
      _snack("Couldn't play that clip. Try again.", kind: RiseToastKind.error);
    } finally {
      if (mounted) {
        setState(() => _playingId = null);
        ref.invalidate(voiceInboxProvider);
      }
    }
  }

  Future<void> _delete(VoiceClip clip) async {
    if (_busy.contains(clip.id)) return;
    setState(() => _busy.add(clip.id));
    try {
      await ref.read(voiceClipServiceProvider).delete(clip);
    } on VoiceClipException catch (e) {
      _snack(e.message, kind: RiseToastKind.error);
    } catch (_) {
      _snack('Something went wrong. Try again.', kind: RiseToastKind.error);
    } finally {
      if (mounted) {
        setState(() => _busy.remove(clip.id));
        ref.invalidate(voiceInboxProvider);
      }
    }
  }

  /// Makes [clip] the wake sound of one of the user's alarms: pick an alarm,
  /// download the clip to a persistent local file, and point that alarm's
  /// soundAsset at the file. The native ring plays the file directly and falls
  /// back to the default tone if it's ever missing, so this can never silence
  /// an alarm.
  Future<void> _setAsAlarm(VoiceClip clip) async {
    if (_busy.contains(clip.id)) return;
    // `.future` resolves to the current alarm list (immediately, since Home
    // already watches this provider) rather than a still-loading snapshot.
    List<Alarm> alarms;
    try {
      alarms = await ref.read(alarmsProvider.future);
    } catch (_) {
      alarms = const [];
    }
    if (!mounted) return;
    if (alarms.isEmpty) {
      _snack('Create an alarm first, then set this clip as its sound.');
      return;
    }
    final chosen = await _pickAlarm(alarms);
    if (chosen == null || !mounted) return;

    setState(() => _busy.add(clip.id));
    try {
      final path = await ref.read(voiceClipServiceProvider).downloadForAlarm(clip);
      await ref
          .read(alarmMutationsProvider)
          .save(chosen.copyWith(soundAsset: path));
      _snack('Set as the sound for ${_alarmTime(chosen)}.',
          kind: RiseToastKind.success);
    } on VoiceClipException catch (e) {
      _snack(e.message, kind: RiseToastKind.error);
    } catch (_) {
      _snack("Couldn't set that as your alarm sound. Try again.",
          kind: RiseToastKind.error);
    } finally {
      if (mounted) setState(() => _busy.remove(clip.id));
    }
  }

  /// A bottom-sheet picker of the user's alarms; resolves to the chosen alarm
  /// or null if dismissed.
  Future<Alarm?> _pickAlarm(List<Alarm> alarms) {
    return showModalBottomSheet<Alarm>(
      context: context,
      backgroundColor: RiseColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(RiseRadii.base)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  RiseSpacing.screen, 18, RiseSpacing.screen, 6),
              child: Text('Set as sound for…', style: RiseText.title),
            ),
            for (final a in alarms)
              GestureDetector(
                key: Key('alarm-pick-${a.id}'),
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(ctx).pop(a),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: RiseSpacing.screen, vertical: 14),
                  child: Row(
                    children: [
                      Icon(Icons.alarm,
                          size: 20, color: RiseColors.textDim),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _alarmLabel(a),
                          style:
                              RiseText.body.copyWith(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  String _alarmLabel(Alarm a) {
    final hasName = a.label.isNotEmpty && a.label != 'Alarm';
    return hasName ? '${_alarmTime(a)} · ${a.label}' : _alarmTime(a);
  }

  String _alarmTime(Alarm a) {
    final mm = a.minute.toString().padLeft(2, '0');
    final use24h = ref.read(currentSettingsProvider).use24HourTime;
    if (use24h) return '${a.hour.toString().padLeft(2, '0')}:$mm';
    return '${a.hour12}:$mm ${a.isAm ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    final inbox = ref.watch(voiceInboxProvider);
    return Scaffold(
      backgroundColor: RiseColors.appBg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              RiseSpacing.screen, 8, RiseSpacing.screen, 40),
          children: [
            _header(),
            const SizedBox(height: 20),
            inbox.when(
              data: (clips) =>
                  clips.isEmpty ? _empty() : Column(children: [
                    for (final c in clips) _clipRow(c),
                  ]),
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              ),
              error: (_, __) => _empty(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() => Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).maybePop(),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Icon(Icons.arrow_back, color: RiseColors.text, size: 22),
            ),
          ),
          const SizedBox(width: 8),
          Text('Voice inbox', style: RiseText.title),
        ],
      );

  Widget _empty() => Padding(
        padding: const EdgeInsets.only(top: 40),
        child: Column(
          children: [
            Icon(Icons.graphic_eq,
                size: 40, color: RiseColors.textFaint),
            const SizedBox(height: 14),
            Text('No voice clips yet',
                style: RiseText.body.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
                'When someone in your crew sends you a clip, it lands here. Open '
                'a friend and tap “Send a voice clip” to send the first one.',
                textAlign: TextAlign.center, style: RiseText.caption),
          ],
        ),
      );

  Widget _clipRow(VoiceClip clip) {
    final playing = _playingId == clip.id;
    final deleting = _busy.contains(clip.id);
    final seconds = clip.duration.inSeconds;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RiseCard(
        child: Row(
          children: [
            GestureDetector(
              key: Key('voice-play-${clip.id}'),
              behavior: HitTestBehavior.opaque,
              onTap: () => _play(clip),
              child: Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: avatarColorFromHex(clip.sender.avatarColor),
                    shape: BoxShape.circle),
                child: Icon(playing ? Icons.stop : Icons.play_arrow,
                    color: RiseColors.primaryText, size: 24),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                            clip.sender.displayName.isNotEmpty
                                ? clip.sender.displayName
                                : '@${clip.sender.username}',
                            style: RiseText.body
                                .copyWith(fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (!clip.isPlayed) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                              color: RiseColors.primary,
                              shape: BoxShape.circle),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text('${seconds}s · ${_ago(clip.createdAt)}',
                      style:
                          RiseText.mono(size: 12, color: RiseColors.textDim)),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Opacity(
              opacity: deleting ? 0.4 : 1,
              child: GestureDetector(
                key: Key('voice-setalarm-${clip.id}'),
                behavior: HitTestBehavior.opaque,
                onTap: deleting ? null : () => _setAsAlarm(clip),
                child: Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.alarm_add,
                      color: RiseColors.textFaint, size: 20),
                ),
              ),
            ),
            Opacity(
              opacity: deleting ? 0.4 : 1,
              child: GestureDetector(
                key: Key('voice-delete-${clip.id}'),
                behavior: HitTestBehavior.opaque,
                onTap: deleting ? null : () => _delete(clip),
                child: Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.delete_outline,
                      color: RiseColors.textFaint, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}
