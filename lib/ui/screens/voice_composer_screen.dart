import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/voice/voice_clip_service.dart';
import '../../data/voice/voice_recorder.dart';
import '../../domain/crew_member.dart';
import '../../domain/voice_recording.dart';
import '../components/rise_card.dart';
import '../components/toast.dart';
import '../state/voice_providers.dart';
import '../theme/avatar_color.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Record a short voice clip (≤30s) and send it to a crew member: tap to record,
/// preview, then send. Recording + playback go through the injectable
/// recorder/player, so this screen is widget-testable with fakes.
class VoiceComposerScreen extends ConsumerStatefulWidget {
  const VoiceComposerScreen({super.key, required this.member});

  final CrewMember member;

  @override
  ConsumerState<VoiceComposerScreen> createState() =>
      _VoiceComposerScreenState();
}

enum _Phase { idle, recording, recorded, sending }

class _VoiceComposerScreenState extends ConsumerState<VoiceComposerScreen> {
  _Phase _phase = _Phase.idle;
  final ValueNotifier<Duration> _elapsed = ValueNotifier(Duration.zero);
  Timer? _ticker;
  VoiceRecording? _recording;
  bool _previewing = false;

  CrewMember get _member => widget.member;

  @override
  void dispose() {
    _ticker?.cancel();
    _elapsed.dispose();
    super.dispose();
  }

  void _toast(String message, {RiseToastKind kind = RiseToastKind.info}) {
    if (!mounted) return;
    RiseToast.show(context, message, kind: kind);
  }

  Future<void> _startRecording() async {
    final recorder = ref.read(voiceRecorderProvider);
    final ok = await recorder.hasPermission();
    if (!ok) {
      _toast('Microphone access is needed to record a clip.',
          kind: RiseToastKind.error);
      return;
    }
    await recorder.start();
    if (!mounted) return;
    _elapsed.value = Duration.zero;
    setState(() {
      _phase = _Phase.recording;
      _recording = null;
    });
    _ticker?.cancel();
    // Only the elapsed-time label listens to `_elapsed`, so these 5-per-second
    // ticks repaint just that label — not the whole composer via setState.
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      _elapsed.value += const Duration(milliseconds: 200);
      if (_elapsed.value >= kMaxVoiceClipDuration) {
        unawaited(_stopRecording()); // hard cap
      }
    });
  }

  Future<void> _stopRecording() async {
    if (_phase != _Phase.recording) return;
    _ticker?.cancel();
    _ticker = null;
    final clip = await ref.read(voiceRecorderProvider).stop();
    if (!mounted) return;
    if (clip == null) {
      setState(() => _phase = _Phase.idle);
      _toast('That recording came up empty — try again.',
          kind: RiseToastKind.error);
      return;
    }
    _elapsed.value = clip.duration;
    setState(() {
      _recording = clip;
      _phase = _Phase.recorded;
    });
  }

  Future<void> _reRecord() async {
    final player = ref.read(voicePlayerProvider);
    await player.stop();
    if (!mounted) return;
    _elapsed.value = Duration.zero;
    setState(() {
      _recording = null;
      _previewing = false;
      _phase = _Phase.idle;
    });
  }

  Future<void> _preview() async {
    final clip = _recording;
    if (clip == null) return;
    final player = ref.read(voicePlayerProvider);
    if (_previewing) {
      await player.stop();
      if (mounted) setState(() => _previewing = false);
      return;
    }
    setState(() => _previewing = true);
    try {
      await player.play(clip.path);
    } catch (_) {
      // ignore playback errors on preview
    }
    if (mounted) setState(() => _previewing = false);
  }

  Future<void> _send() async {
    final clip = _recording;
    if (clip == null || _phase == _Phase.sending) return;
    await ref.read(voicePlayerProvider).stop();
    setState(() => _phase = _Phase.sending);
    try {
      await ref
          .read(voiceClipServiceProvider)
          .send(targetId: _member.id, recording: clip);
      if (!mounted) return;
      Navigator.of(context).maybePop();
      _toast('Sent to @${_member.username} 🎙️', kind: RiseToastKind.success);
    } on VoiceClipException catch (e) {
      if (!mounted) return;
      setState(() => _phase = _Phase.recorded);
      _toast(e.message, kind: RiseToastKind.error);
    } catch (_) {
      if (!mounted) return;
      setState(() => _phase = _Phase.recorded);
      _toast('Something went wrong. Try again.', kind: RiseToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RiseColors.appBg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              RiseSpacing.screen, 8, RiseSpacing.screen, 40),
          children: [
            _header(),
            const SizedBox(height: 8),
            Text(
                'Record a short hello, a pep talk, or your best impression of an '
                'alarm — @${_member.username} will hear it in their inbox.',
                style: RiseText.caption),
            const SizedBox(height: 28),
            _recorderCard(),
            const SizedBox(height: 20),
            if (_phase == _Phase.recorded || _phase == _Phase.sending)
              _sendRow(),
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
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: avatarColorFromHex(_member.avatarColor),
                shape: BoxShape.circle),
            child: Text(
              (_member.username.isNotEmpty ? _member.username : '?')
                  .characters
                  .first
                  .toUpperCase(),
              style: RiseText.body.copyWith(
                  color: RiseColors.primaryText, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Voice clip for @${_member.username}',
                style: RiseText.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      );

  Widget _recorderCard() {
    return RiseCard(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      child: Column(
        children: [
          _ElapsedLabel(elapsed: _elapsed),
          const SizedBox(height: 6),
          Text(_hint(),
              textAlign: TextAlign.center,
              style: RiseText.caption.copyWith(color: RiseColors.textDim)),
          const SizedBox(height: 24),
          _primaryControl(),
        ],
      ),
    );
  }

  Widget _primaryControl() {
    switch (_phase) {
      case _Phase.idle:
        return _circleButton(
          key: const Key('voice-record-button'),
          icon: Icons.mic,
          bg: RiseColors.primary,
          fg: RiseColors.primaryText,
          onTap: _startRecording,
        );
      case _Phase.recording:
        return _circleButton(
          key: const Key('voice-stop-button'),
          icon: Icons.stop,
          bg: RiseColors.danger,
          fg: Colors.white,
          onTap: _stopRecording,
        );
      case _Phase.recorded:
      case _Phase.sending:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _circleButton(
              key: const Key('voice-preview-button'),
              icon: _previewing ? Icons.stop : Icons.play_arrow,
              bg: RiseColors.card,
              fg: RiseColors.text,
              border: true,
              onTap: _phase == _Phase.sending ? null : _preview,
            ),
            const SizedBox(width: 20),
            _circleButton(
              key: const Key('voice-rerecord-button'),
              icon: Icons.refresh,
              bg: RiseColors.card,
              fg: RiseColors.textDim,
              border: true,
              small: true,
              onTap: _phase == _Phase.sending ? null : _reRecord,
            ),
          ],
        );
    }
  }

  Widget _sendRow() => GestureDetector(
        key: const Key('voice-send-button'),
        behavior: HitTestBehavior.opaque,
        onTap: _phase == _Phase.sending ? null : _send,
        child: Opacity(
          opacity: _phase == _Phase.sending ? 0.5 : 1,
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(
              color: RiseColors.primary,
              borderRadius: BorderRadius.circular(RiseRadii.base),
            ),
            child: Text(
                _phase == _Phase.sending
                    ? 'Sending…'
                    : 'Send to @${_member.username}',
                style: RiseText.body.copyWith(
                    color: RiseColors.primaryText,
                    fontWeight: FontWeight.w600,
                    fontSize: 15)),
          ),
        ),
      );

  Widget _circleButton({
    required Key key,
    required IconData icon,
    required Color bg,
    required Color fg,
    required VoidCallback? onTap,
    bool border = false,
    bool small = false,
  }) {
    final size = small ? 52.0 : 72.0;
    return Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: GestureDetector(
        key: key,
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            border: border ? Border.all(color: RiseColors.border) : null,
          ),
          child: Icon(icon, color: fg, size: small ? 24 : 34),
        ),
      ),
    );
  }

  String _hint() => switch (_phase) {
        _Phase.idle => 'Tap to record · up to 30s',
        _Phase.recording => 'Recording… tap to stop',
        _Phase.recorded => _previewing ? 'Playing…' : 'Preview, then send',
        _Phase.sending => 'Sending your clip…',
      };
}

/// The big mono readout of recording/clip length. It listens to [elapsed] on
/// its own, so while recording the ~5-per-second ticks repaint only this label
/// instead of rebuilding the whole composer.
class _ElapsedLabel extends StatelessWidget {
  const _ElapsedLabel({required this.elapsed});

  final ValueListenable<Duration> elapsed;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Duration>(
      valueListenable: elapsed,
      builder: (_, value, __) {
        final capped =
            value > kMaxVoiceClipDuration ? kMaxVoiceClipDuration : value;
        final s = capped.inSeconds;
        return Text('0:${s.toString().padLeft(2, '0')}',
            style: RiseText.mono(size: 40, weight: FontWeight.w500));
      },
    );
  }
}
