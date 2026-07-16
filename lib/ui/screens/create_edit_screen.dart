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

/// Mission keys ↔ display labels. The `SoundChips` pill row is a generic
/// single-select chip strip, reused here for the mission picker.
const Map<String, String> _missionLabels = {
  'none': 'None',
  'math': 'Math',
  'hold': 'Hold',
  'tap': 'Tap',
  'memory': 'Memory',
};

class CreateEditScreen extends ConsumerStatefulWidget {
  const CreateEditScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  ConsumerState<CreateEditScreen> createState() => _CreateEditScreenState();
}

class _CreateEditScreenState extends ConsumerState<CreateEditScreen> {
  late final TextEditingController _label;

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
    await ref.read(alarmMutationsProvider).save(draft);
    if (!mounted) return;
    ref.read(toastProvider.notifier).state = 'Alarm saved';
    ref.read(draftProvider.notifier).clear();
    widget.onDone();
  }

  Future<void> _delete(int id) async {
    await ref.read(alarmMutationsProvider).delete(id);
    if (!mounted) return;
    ref.read(toastProvider.notifier).state = 'Alarm deleted';
    ref.read(draftProvider.notifier).clear();
    widget.onDone();
  }

  void _cancel() {
    ref.read(draftProvider.notifier).clear();
    widget.onDone();
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
          PrimaryButton(label: 'Save alarm', onPressed: () => _save(draft)),
          if (isEdit) ...[
            const SizedBox(height: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _delete(draft.id),
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
