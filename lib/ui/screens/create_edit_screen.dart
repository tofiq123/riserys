import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/alarm.dart';
import '../../domain/alarm_sounds.dart';
import '../components/day_chips.dart';
import '../components/rise_buttons.dart';
import '../components/rise_card.dart';
import '../components/rise_switch.dart';
import '../components/section_label.dart';
import '../components/segmented.dart';
import '../components/sound_chips.dart';
import '../components/time_dial.dart';
import '../state/alarm_providers.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'qr_register_screen.dart';

/// Mission keys ↔ display labels. The `SoundChips` pill row is a generic
/// single-select chip strip, reused here for the mission picker.
const Map<String, String> _missionLabels = {
  'none': 'None',
  'math': 'Math',
  'hold': 'Hold',
  'tap': 'Tap',
  'memory': 'Memory',
  'pvt': 'Alertness (PVT)',
  'typing': 'Type a phrase',
  'shake': 'Shake it off',
  'qr': 'Scan a code',
  'steps': 'Walk it off',
};

class CreateEditScreen extends ConsumerStatefulWidget {
  const CreateEditScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  ConsumerState<CreateEditScreen> createState() => _CreateEditScreenState();
}

class _CreateEditScreenState extends ConsumerState<CreateEditScreen> {
  late final TextEditingController _label;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Seed once from the draft set before navigation; the controller then owns
    // the text so watching the draft in build() won't fight the user's typing.
    _label = TextEditingController(text: ref.read(draftProvider)?.label ?? '');
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  void _update(Alarm next) => ref.read(draftProvider.notifier).update(next);

  Future<void> _save(Alarm draft) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(alarmMutationsProvider).save(draft);
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    if (!mounted) return;
    ref.read(toastProvider.notifier).state = 'Alarm saved';
    ref.read(draftProvider.notifier).clear();
    widget.onDone();
  }

  Future<void> _delete(int id) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(alarmMutationsProvider).delete(id);
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    if (!mounted) return;
    ref.read(toastProvider.notifier).state = 'Alarm deleted';
    ref.read(draftProvider.notifier).clear();
    widget.onDone();
  }

  void _cancel() {
    ref.read(draftProvider.notifier).clear();
    widget.onDone();
  }

  /// Scans a QR/barcode once and stores it as the alarm's registered code
  /// ([Alarm.missionData]) — what the 'qr' dismiss mission will require.
  Future<void> _registerQr() async {
    final code = await registerQrCode(context);
    if (!mounted || code == null) return;
    final draft = ref.read(draftProvider);
    if (draft == null) return;
    _update(draft.copyWith(missionData: code));
    ref.read(toastProvider.notifier).state = 'QR code registered';
  }

  /// The "Register QR code" control shown for the 'qr' mission. When no code is
  /// registered the mission accepts any scan (never a trap), which this states
  /// plainly so the choice is explicit.
  Widget _qrRegisterRow(Alarm draft) {
    final hasCode = (draft.missionData?.trim() ?? '').isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(hasCode ? Icons.check_circle : Icons.qr_code_2,
                size: 18,
                color: hasCode ? RiseColors.positive : RiseColors.textDim),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hasCode
                    ? 'Code registered — scan it to dismiss'
                    : 'No code yet — any scan will dismiss',
                style: RiseText.caption,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SecondaryButton(
          label: hasCode ? 'Re-register QR code' : 'Register QR code',
          icon: Icons.qr_code_scanner,
          onPressed: _busy ? null : _registerQr,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(draftProvider);
    if (draft == null) return const SizedBox.shrink();
    final isEdit = draft.id != 0;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            RiseSpacing.screen, 8, RiseSpacing.screen, 40),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GhostButton(label: 'Cancel', onPressed: _cancel),
              Text(isEdit ? 'Edit alarm' : 'New alarm', style: RiseText.title),
              const SizedBox(width: 64), // balances the Cancel button
            ],
          ),
          const SizedBox(height: 12),
          RiseCard(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: TimeDial(
              value: (hour12: draft.hour12, minute: draft.minute, isAm: draft.isAm),
              onChanged: (t) => _update(draft.copyWith(
                hour: Alarm.to24Hour(t.hour12, t.isAm),
                minute: t.minute,
                clearLastDismissedAt: true, // editing time clears a stale dismissal
              )),
            ),
          ),
          _section('Repeat', DayChips(
            days: draft.days,
            onToggle: (i) {
              final next = {...draft.days};
              next.contains(i) ? next.remove(i) : next.add(i);
              _update(draft.copyWith(days: next));
            },
          ),
          trailing: Text(repeatLabel(draft.days), style: RiseText.caption)),
          _section('Label', TextField(
            controller: _label,
            onChanged: (v) => _update(draft.copyWith(label: v)),
            style: RiseText.body,
            cursorColor: RiseColors.primary,
            decoration: InputDecoration(
              hintText: 'Alarm',
              hintStyle: RiseText.body.copyWith(color: RiseColors.textFaint),
              filled: true,
              fillColor: RiseColors.surface2,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: _fieldBorder(RiseColors.border),
              enabledBorder: _fieldBorder(RiseColors.border),
              focusedBorder: _fieldBorder(RiseColors.primary),
            ),
          )),
          _section('Sound', SoundChips(
            sounds: kAlarmSounds.map((s) => s.label).toList(),
            selected: soundLabelFor(draft.soundAsset),
            onChanged: (label) =>
                _update(draft.copyWith(soundAsset: soundAssetFor(label))),
          )),
          _section('Wake mission', SoundChips(
            sounds: _missionLabels.values.toList(),
            selected: _missionLabels[draft.mission] ?? _missionLabels['none']!,
            onChanged: (label) {
              final key = _missionLabels.entries
                  .firstWhere((e) => e.value == label)
                  .key;
              _update(draft.copyWith(mission: key));
            },
          )),
          if (draft.mission != 'none')
            _section('Difficulty', SegmentedControl<String>(
              segments: const [
                (value: 'easy', label: 'Easy'),
                (value: 'medium', label: 'Medium'),
                (value: 'hard', label: 'Hard'),
              ],
              selected: draft.missionDiff,
              onChanged: (d) => _update(draft.copyWith(missionDiff: d)),
            )),
          if (draft.mission != 'none')
            _section('Repeat mission', SegmentedControl<int>(
              segments: const [
                (value: 1, label: '1×'),
                (value: 2, label: '2×'),
                (value: 3, label: '3×'),
              ],
              selected: draft.missionCount,
              onChanged: (n) => _update(draft.copyWith(missionCount: n)),
            )),
          if (draft.mission == 'qr')
            _section('QR code', _qrRegisterRow(draft)),
          const SizedBox(height: 20),
          RiseCard(
            radius: RiseRadii.base,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Vibrate', style: RiseText.body),
                RiseSwitch(
                  value: draft.vibrate,
                  onChanged: (v) => _update(draft.copyWith(vibrate: v)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          PrimaryButton(
              label: 'Save alarm',
              onPressed: _busy ? null : () => _save(draft)),
          if (isEdit) ...[
            const SizedBox(height: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _busy ? null : () => _delete(draft.id),
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 13),
                child: Text('Delete alarm',
                    style: RiseText.body.copyWith(
                        color: RiseColors.danger, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static OutlineInputBorder _fieldBorder(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(RiseRadii.base),
        borderSide: BorderSide(color: color),
      );

  Widget _section(String label, Widget child, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [SectionLabel(label), if (trailing != null) trailing],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
