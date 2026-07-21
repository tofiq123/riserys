import 'package:flutter/material.dart';

import '../../domain/alarm.dart';
import '../../domain/premium_feature.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'rise_buttons.dart';
import 'section_label.dart';
import 'segmented.dart';

/// Mission keys ↔ display labels, in picker order. Public so the Create/Edit
/// screen can render the collapsed "Wake mission" row's title from the same
/// source of truth.
const Map<String, String> kMissionLabels = {
  'none': 'None',
  'math': 'Math',
  'tap': 'Tap',
  'hold': 'Hold',
  'memory': 'Memory',
  'pvt': 'Alertness (PVT)',
  'typing': 'Type a phrase',
  'shake': 'Shake it off',
  'qr': 'Scan a code',
  'steps': 'Walk it off',
  'photo': 'Snap a spot',
  'eyes': 'Keep your eyes open',
};

/// One-line descriptions shown under each mission label in the picker.
const Map<String, String> kMissionDescriptions = {
  'none': 'Just slide to wake',
  'math': 'Solve a quick problem',
  'tap': 'Tap a target a few times',
  'hold': 'Hold a button until it fills',
  'memory': 'Repeat a pattern',
  'pvt': 'A reaction test that measures how awake you are',
  'typing': 'Type a short phrase',
  'shake': 'Shake your phone until it counts',
  'qr': "Scan a QR you've placed across the room",
  'steps': 'Walk a number of steps',
  'photo': 'Photograph a spot you registered',
  'eyes': 'Hold your eyes open to the camera',
};

/// The missions whose behaviour is shaped by [Alarm.missionDiff]. Mirrors what
/// `buildMission` actually forwards a difficulty to — `qr`/`photo` are driven
/// by [Alarm.missionData] instead, and `none` has no config, so none of those
/// show a Difficulty control.
const Set<String> kDifficultyMissions = {
  'math',
  'tap',
  'hold',
  'memory',
  'pvt',
  'typing',
  'shake',
  'steps',
  'eyes',
};

/// A compact one-line summary of a mission's config for the collapsed row, e.g.
/// "Medium · 2×" (or "2×" for a mission that ignores difficulty, or "" for a
/// mission with no config / count 1). The mission label itself is shown
/// separately by the caller.
String missionConfigSummary(Alarm a) {
  if (a.mission == 'none' || !kMissionLabels.containsKey(a.mission)) return '';
  final parts = <String>[];
  if (kDifficultyMissions.contains(a.mission)) {
    parts.add(_capitalize(a.missionDiff));
  }
  if (a.missionCount > 1) parts.add('${a.missionCount}×');
  return parts.join(' · ');
}

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// Opens the browsable mission picker as a modal bottom sheet and resolves to
/// the edited [Alarm] (mission + its config applied), or null if the user
/// cancelled (keep the current mission).
///
/// Gating and the camera register flows are injected so the sheet stays free of
/// Riverpod and platform channels (and is widget-testable with fakes):
/// - [missionsLocked] / [chainsLocked] come from the premium gate; a locked
///   choice calls [onOpenPaywall] instead of selecting.
/// - [onRegisterQr] / [onRegisterPhoto] run the one-shot scanner/camera and
///   resolve to the registered payload/hash, or null if the user backed out.
Future<Alarm?> showMissionPickerSheet(
  BuildContext context, {
  required Alarm draft,
  required bool missionsLocked,
  required bool chainsLocked,
  required VoidCallback onOpenPaywall,
  required Future<String?> Function() onRegisterQr,
  required Future<String?> Function() onRegisterPhoto,
}) {
  return showModalBottomSheet<Alarm>(
    context: context,
    isScrollControlled: true,
    backgroundColor: RiseColors.card,
    barrierColor: const Color(0x66000000),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(RiseRadii.lg)),
    ),
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: 0.82,
      child: MissionPickerSheet(
        initial: draft,
        missionsLocked: missionsLocked,
        chainsLocked: chainsLocked,
        onOpenPaywall: onOpenPaywall,
        onRegisterQr: onRegisterQr,
        onRegisterPhoto: onRegisterPhoto,
        onConfirm: (a) => Navigator.of(sheetContext).pop(a),
        onCancel: () => Navigator.of(sheetContext).pop(),
      ),
    ),
  );
}

/// The mission browser content: a scrollable list of missions (label + one-line
/// description), and — for the selected mission — its contextual options
/// (Difficulty, Repeat, and a Register action for `qr`/`photo`) pinned above a
/// "Done" button. Self-contained (no Navigator/Riverpod dependency) so it can be
/// pumped directly in a widget test.
class MissionPickerSheet extends StatefulWidget {
  const MissionPickerSheet({
    super.key,
    required this.initial,
    required this.missionsLocked,
    required this.chainsLocked,
    required this.onOpenPaywall,
    required this.onRegisterQr,
    required this.onRegisterPhoto,
    required this.onConfirm,
    required this.onCancel,
  });

  final Alarm initial;
  final bool missionsLocked;
  final bool chainsLocked;
  final VoidCallback onOpenPaywall;
  final Future<String?> Function() onRegisterQr;
  final Future<String?> Function() onRegisterPhoto;
  final ValueChanged<Alarm> onConfirm;
  final VoidCallback onCancel;

  @override
  State<MissionPickerSheet> createState() => _MissionPickerSheetState();
}

class _MissionPickerSheetState extends State<MissionPickerSheet> {
  /// The working copy edited in the sheet; applied on Done, discarded on Cancel.
  late Alarm _draft = widget.initial;

  bool _isLocked(String key) =>
      isPremiumMissionKey(key) && widget.missionsLocked;

  void _selectMission(String key) {
    if (_isLocked(key)) {
      widget.onOpenPaywall();
      return;
    }
    if (key == _draft.mission) return;
    setState(() {
      // Changing to a different mission clears any stale registration so a QR
      // payload can't masquerade as a photo hash (and vice-versa).
      _draft = _draft.copyWith(mission: key, clearMissionData: true);
    });
  }

  void _selectDiff(String diff) =>
      setState(() => _draft = _draft.copyWith(missionDiff: diff));

  void _selectCount(int n) {
    if (n > kFreeMissionCount && widget.chainsLocked) {
      widget.onOpenPaywall();
      return;
    }
    setState(() => _draft = _draft.copyWith(missionCount: n));
  }

  Future<void> _registerQr() async {
    final code = await widget.onRegisterQr();
    if (!mounted || code == null) return;
    setState(() => _draft = _draft.copyWith(missionData: code));
  }

  Future<void> _registerPhoto() async {
    final hash = await widget.onRegisterPhoto();
    if (!mounted || hash == null) return;
    setState(() => _draft = _draft.copyWith(missionData: hash));
  }

  @override
  Widget build(BuildContext context) {
    final mission = _draft.mission;
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
              Text('Wake mission', style: RiseText.title),
              GhostButton(label: 'Cancel', onPressed: widget.onCancel),
            ],
          ),
        ),
        Divider(height: 1, thickness: 1, color: RiseColors.divider),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 8),
            children: [
              for (final key in kMissionLabels.keys)
                _MissionTile(
                  label: kMissionLabels[key]!,
                  description: kMissionDescriptions[key] ?? '',
                  selected: key == mission,
                  locked: _isLocked(key),
                  onTap: () => _selectMission(key),
                ),
            ],
          ),
        ),
        if (mission != 'none' && kMissionLabels.containsKey(mission))
          _MissionConfig(
            mission: mission,
            diff: _draft.missionDiff,
            count: _draft.missionCount,
            missionData: _draft.missionData,
            chainsLocked: widget.chainsLocked,
            onDiff: _selectDiff,
            onCount: _selectCount,
            onRegisterQr: _registerQr,
            onRegisterPhoto: _registerPhoto,
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                RiseSpacing.screen, 10, RiseSpacing.screen, 12),
            child: PrimaryButton(
              label: 'Done',
              onPressed: () => widget.onConfirm(_draft),
            ),
          ),
        ),
      ],
    );
  }
}

/// One tappable mission row: label + one-line description, a lock glyph when the
/// option is premium-gated, and a check when it is the current selection.
class _MissionTile extends StatelessWidget {
  const _MissionTile({
    required this.label,
    required this.description,
    required this.selected,
    required this.locked,
    required this.onTap,
  });

  final String label;
  final String description;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        color: selected ? RiseColors.accentSoft : const Color(0x00000000),
        padding: const EdgeInsets.symmetric(
            horizontal: RiseSpacing.screen, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: RiseText.body.copyWith(
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(description, style: RiseText.caption),
                  ],
                ],
              ),
            ),
            if (locked) ...[
              Icon(Icons.lock_outline, size: 16, color: RiseColors.textDim),
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

/// The contextual options for the selected mission, pinned above "Done":
/// Difficulty (for missions that use it), Repeat (the mission chain), and a
/// Register action for `qr`/`photo`.
class _MissionConfig extends StatelessWidget {
  const _MissionConfig({
    required this.mission,
    required this.diff,
    required this.count,
    required this.missionData,
    required this.chainsLocked,
    required this.onDiff,
    required this.onCount,
    required this.onRegisterQr,
    required this.onRegisterPhoto,
  });

  final String mission;
  final String diff;
  final int count;
  final String? missionData;
  final bool chainsLocked;
  final ValueChanged<String> onDiff;
  final ValueChanged<int> onCount;
  final VoidCallback onRegisterQr;
  final VoidCallback onRegisterPhoto;

  @override
  Widget build(BuildContext context) {
    final showDiff = kDifficultyMissions.contains(mission);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: RiseColors.surface2,
        border: Border(top: BorderSide(color: RiseColors.divider)),
      ),
      padding: const EdgeInsets.fromLTRB(
          RiseSpacing.screen, 14, RiseSpacing.screen, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showDiff) ...[
            const SectionLabel('Difficulty'),
            const SizedBox(height: 8),
            SegmentedControl<String>(
              segments: const [
                (value: 'easy', label: 'Easy'),
                (value: 'medium', label: 'Medium'),
                (value: 'hard', label: 'Hard'),
              ],
              selected: diff,
              onChanged: onDiff,
            ),
            const SizedBox(height: 14),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SectionLabel('Repeat'),
              if (chainsLocked)
                Icon(Icons.lock_outline, size: 14, color: RiseColors.textDim),
            ],
          ),
          const SizedBox(height: 8),
          SegmentedControl<int>(
            segments: const [
              (value: 1, label: '1×'),
              (value: 2, label: '2×'),
              (value: 3, label: '3×'),
            ],
            selected: count,
            onChanged: onCount,
          ),
          if (mission == 'qr') ...[
            const SizedBox(height: 14),
            _RegisterRow(
              has: (missionData?.trim() ?? '').isNotEmpty,
              hasText: 'Code registered — scan it to dismiss',
              emptyText: 'No code yet — any scan will dismiss',
              hasLabel: 'Re-register QR code',
              emptyLabel: 'Register QR code',
              icon: Icons.qr_code_scanner,
              onPressed: onRegisterQr,
            ),
          ],
          if (mission == 'photo') ...[
            const SizedBox(height: 14),
            _RegisterRow(
              has: (missionData?.trim() ?? '').isNotEmpty,
              hasText: 'Spot registered — snap it to dismiss',
              emptyText: 'No spot yet — any photo will dismiss',
              hasLabel: 'Re-register photo',
              emptyLabel: 'Register photo',
              icon: Icons.photo_camera,
              onPressed: onRegisterPhoto,
            ),
          ],
        ],
      ),
    );
  }
}

/// The status line + register button for the `qr`/`photo` missions. When
/// nothing is registered the mission accepts the first scan/photo (never a
/// trap), which the status line states plainly so the choice is explicit.
class _RegisterRow extends StatelessWidget {
  const _RegisterRow({
    required this.has,
    required this.hasText,
    required this.emptyText,
    required this.hasLabel,
    required this.emptyLabel,
    required this.icon,
    required this.onPressed,
  });

  final bool has;
  final String hasText;
  final String emptyText;
  final String hasLabel;
  final String emptyLabel;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(has ? Icons.check_circle : Icons.info_outline,
                size: 18,
                color: has ? RiseColors.positive : RiseColors.textDim),
            const SizedBox(width: 8),
            Expanded(
              child: Text(has ? hasText : emptyText, style: RiseText.caption),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SecondaryButton(
          label: has ? hasLabel : emptyLabel,
          icon: icon,
          onPressed: onPressed,
        ),
      ],
    );
  }
}
