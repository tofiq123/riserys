import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../domain/alarm_sounds.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'rise_buttons.dart';

/// Plays short tone previews for the sound picker. Abstracted so the picker can
/// be widget-tested with a fake — the real implementation uses just_audio.
/// Every method is best-effort and MUST NOT throw.
abstract class SoundPreviewer {
  /// Preview the tone at [assetKey] (a Flutter asset-bundle key), replacing
  /// whatever is currently playing.
  Future<void> play(String assetKey);

  /// Stop any current preview.
  Future<void> stop();

  /// Release resources. The picker's owner calls this once the sheet closes.
  Future<void> dispose();
}

/// The default [SoundPreviewer], backed by a single lazily-created just_audio
/// player. All playback is wrapped so a platform/decode failure is a silent
/// no-op — a failed preview never blocks selecting the sound.
class JustAudioPreviewer implements SoundPreviewer {
  AudioPlayer? _player;

  @override
  Future<void> play(String assetKey) async {
    final p = _player ??= AudioPlayer();
    try {
      await p.stop();
      await p.setAsset(assetKey);
      await p.play();
    } catch (_) {
      // Best-effort preview only.
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _player?.stop();
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    try {
      await _player?.dispose();
    } catch (_) {}
    _player = null;
  }
}

/// Opens the categorized sound browser as a modal bottom sheet and resolves to
/// the chosen asset path, or null if the user cancelled (keep the old sound).
///
/// [currentAsset] is the alarm's current `soundAsset` — a bundled tone, the
/// Default asset, or a voice-clip file path (shown as a pinned "Voice clip"
/// row). Owns the [JustAudioPreviewer] lifecycle: it is disposed after the
/// sheet closes.
Future<String?> showSoundPickerSheet(
  BuildContext context, {
  required String currentAsset,
}) async {
  final previewer = JustAudioPreviewer();
  try {
    return await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: RiseColors.card,
      barrierColor: const Color(0x66000000),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(RiseRadii.lg)),
      ),
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.82,
        child: SoundPickerSheet(
          initialAsset: currentAsset,
          previewer: previewer,
          onConfirm: (asset) => Navigator.of(sheetContext).pop(asset),
          onCancel: () => Navigator.of(sheetContext).pop(),
        ),
      ),
    );
  } finally {
    await previewer.dispose();
  }
}

/// The categorized sound browser content: a pinned Default (and a "Voice clip"
/// row when the current sound is a downloaded file), then one section per
/// [kSoundCategories] entry. Tapping a tone previews it and marks it selected;
/// "Done" confirms the selection, "Cancel" keeps the old one.
///
/// Self-contained (no Navigator dependency) so it can be pumped directly in a
/// widget test with a fake [SoundPreviewer].
class SoundPickerSheet extends StatefulWidget {
  const SoundPickerSheet({
    super.key,
    required this.initialAsset,
    required this.previewer,
    required this.onConfirm,
    required this.onCancel,
  });

  final String initialAsset;
  final SoundPreviewer previewer;
  final ValueChanged<String> onConfirm;
  final VoidCallback onCancel;

  @override
  State<SoundPickerSheet> createState() => _SoundPickerSheetState();
}

class _SoundPickerSheetState extends State<SoundPickerSheet> {
  /// The asset currently selected (applied on Done). Starts from the alarm's
  /// current sound so re-opening shows the existing choice checked.
  late String _selected = widget.initialAsset;

  /// The asset whose preview is currently playing, or null. Distinct from
  /// [_selected]: tapping the selected/playing tone again stops preview but
  /// keeps it selected.
  String? _playing;

  /// The flat row list (headers + tones), computed once. Lazy-built by the
  /// ListView so 66 rows stay snappy.
  late final List<_Row> _rows = _buildRows();

  List<_Row> _buildRows() {
    // A voice-clip file sound is not in the catalog — synthesize a pinned row
    // so it's visible and the user can switch away from it to a bundled tone.
    final voice = isFileSound(widget.initialAsset)
        ? AlarmSound(kVoiceSoundLabel, widget.initialAsset, kDefaultCategory.key)
        : null;
    return [
      _Row.tone(kDefaultSound),
      if (voice != null) _Row.tone(voice),
      for (final cat in kSoundCategories) ...[
        _Row.header(cat.label),
        for (final s in soundsInCategory(cat.key)) _Row.tone(s),
      ],
    ];
  }

  @override
  void dispose() {
    // Best-effort stop; the owner disposes the previewer itself.
    unawaited(widget.previewer.stop());
    super.dispose();
  }

  void _onTapTone(AlarmSound s) {
    setState(() => _selected = s.asset);
    final key = previewAssetKeyFor(s.asset);
    if (key == null) {
      // Default or a voice clip: selectable but nothing to preview.
      _stopPreview();
      return;
    }
    if (_playing == s.asset) {
      _stopPreview(); // re-tap the playing tone → stop
      return;
    }
    setState(() => _playing = s.asset);
    unawaited(widget.previewer.play(key));
  }

  void _stopPreview() {
    if (_playing != null) setState(() => _playing = null);
    unawaited(widget.previewer.stop());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Grab handle.
        Container(
          margin: const EdgeInsets.only(top: 10, bottom: 4),
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: RiseColors.border,
            borderRadius: BorderRadius.circular(RiseRadii.pill),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(RiseSpacing.screen, 8, 8, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Sound', style: RiseText.title),
              GhostButton(label: 'Cancel', onPressed: widget.onCancel),
            ],
          ),
        ),
        Divider(height: 1, thickness: 1, color: RiseColors.divider),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 8),
            itemCount: _rows.length,
            itemBuilder: (context, i) {
              final row = _rows[i];
              if (row.isHeader) return _CategoryHeader(label: row.label!);
              final s = row.sound!;
              return _ToneTile(
                label: s.label,
                selected: s.asset == _selected,
                playing: s.asset == _playing,
                // The Default tone and voice clips have no bundled preview, so
                // they show no play affordance (tapping only selects them).
                previewable: previewAssetKeyFor(s.asset) != null,
                onTap: () => _onTapTone(s),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                RiseSpacing.screen, 10, RiseSpacing.screen, 12),
            child: PrimaryButton(
              label: 'Done',
              onPressed: () => widget.onConfirm(_selected),
            ),
          ),
        ),
      ],
    );
  }
}

/// One category section header (e.g. "GENTLE"). A full-width tinted band with
/// a high-contrast label so the categories read at a glance while scrolling —
/// the previous dim 11px section label was easy to miss on device.
class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(RiseSpacing.screen, 9, RiseSpacing.screen, 9),
      decoration: BoxDecoration(
        // appBg reads distinctly against the sheet's card surface in both
        // themes (a light-grey band on white; a near-black band on dark card).
        color: RiseColors.appBg,
        border: Border(
          top: BorderSide(color: RiseColors.divider),
          bottom: BorderSide(color: RiseColors.divider),
        ),
      ),
      child: Text(
        label.toUpperCase(),
        style: RiseText.sectionLabel.copyWith(
          color: RiseColors.text,
          fontSize: 12,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

/// A single tappable tone row: label on the left, a persistent play/stop glyph
/// (so previewing is always discoverable — a play arrow when idle, a volume
/// glyph while previewing), and a check on the right when selected. The
/// selected row gets a soft highlight. Non-previewable rows ([previewable] is
/// false — Default, voice clips) show no play glyph.
class _ToneTile extends StatelessWidget {
  const _ToneTile({
    required this.label,
    required this.selected,
    required this.playing,
    required this.previewable,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool playing;
  final bool previewable;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        color: selected ? RiseColors.accentSoft : const Color(0x00000000),
        padding: const EdgeInsets.symmetric(
            horizontal: RiseSpacing.screen, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: RiseText.body.copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (previewable) ...[
              Icon(
                playing ? Icons.volume_up_rounded : Icons.play_arrow_rounded,
                size: playing ? 17 : 19,
                color: playing ? RiseColors.text : RiseColors.textFaint,
              ),
              const SizedBox(width: 10),
            ],
            if (selected)
              Icon(Icons.check_rounded, size: 19, color: RiseColors.primary),
          ],
        ),
      ),
    );
  }
}

/// A flat picker row — either a category header or a tone. Kept minimal so the
/// ListView can build lazily.
class _Row {
  const _Row.header(this.label)
      : sound = null,
        isHeader = true;
  const _Row.tone(this.sound)
      : label = null,
        isHeader = false;

  final String? label;
  final AlarmSound? sound;
  final bool isHeader;
}
