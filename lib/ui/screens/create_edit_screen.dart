import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/alarm.dart';
import '../../domain/alarm_sounds.dart';
import '../../domain/premium_feature.dart';
import '../components/day_chips.dart';
import '../components/mission_picker_sheet.dart';
import '../components/rise_buttons.dart';
import '../components/rise_card.dart';
import '../components/rise_switch.dart';
import '../components/section_label.dart';
import '../components/segmented.dart';
import '../components/sound_picker_sheet.dart';
import '../components/time_dial.dart';
import '../components/toast.dart';
import '../state/alarm_providers.dart';
import '../state/entitlement_providers.dart';
import '../state/settings_providers.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'paywall_screen.dart';
import 'photo_register_screen.dart';
import 'qr_register_screen.dart';

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

  /// Opens the categorized sound browser and applies the chosen tone to the
  /// draft. Cancelling (null) keeps the current sound. Re-reads the draft after
  /// the async gap so a concurrent edit isn't clobbered.
  Future<void> _openSoundPicker(Alarm draft) async {
    final chosen =
        await showSoundPickerSheet(context, currentAsset: draft.soundAsset);
    if (!mounted || chosen == null) return;
    final latest = ref.read(draftProvider);
    if (latest == null) return;
    _update(latest.copyWith(soundAsset: chosen));
  }

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
    RiseToast.show(context, 'Alarm saved', kind: RiseToastKind.success);
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
    RiseToast.show(context, 'Alarm deleted');
    ref.read(draftProvider.notifier).clear();
    widget.onDone();
  }

  void _cancel() {
    ref.read(draftProvider.notifier).clear();
    widget.onDone();
  }

  /// Opens the browsable mission picker and applies the chosen mission + its
  /// config to the draft. Cancelling (null) keeps the current mission. Re-reads
  /// the draft after the async gap so a concurrent edit isn't clobbered. The
  /// register (QR/photo) flows run from inside the sheet via the injected
  /// callbacks below.
  Future<void> _openMissionPicker(
      Alarm draft, bool missionsLocked, bool chainsLocked) async {
    final result = await showMissionPickerSheet(
      context,
      draft: draft,
      missionsLocked: missionsLocked,
      chainsLocked: chainsLocked,
      onOpenPaywall: () => openPaywall(context),
      onRegisterQr: () => registerQrCode(context),
      onRegisterPhoto: () => registerReferencePhoto(context),
    );
    if (!mounted || result == null) return;
    final latest = ref.read(draftProvider);
    if (latest == null) return;
    // Only the mission fields are owned by the sheet; apply them onto the latest
    // draft. `clearMissionData` when the sheet returns no registration so a
    // stale QR/photo can't survive a mission switch.
    _update(latest.copyWith(
      mission: result.mission,
      missionDiff: result.missionDiff,
      missionCount: result.missionCount,
      missionData: result.missionData,
      clearMissionData: result.missionData == null,
    ));
  }

  /// The tappable "Wake mission" row (mirrors [_soundRow]): shows the current
  /// mission's label with a compact config summary (e.g. "Scan a code · 2×"),
  /// and opens the browsable mission picker on tap.
  Widget _missionRow(Alarm draft, bool missionsLocked, bool chainsLocked) {
    final label = kMissionLabels[draft.mission] ?? kMissionLabels['none']!;
    final summary = missionConfigSummary(draft);
    return GestureDetector(
      key: const Key('wake-mission-row'),
      behavior: HitTestBehavior.opaque,
      onTap: _busy
          ? null
          : () => _openMissionPicker(draft, missionsLocked, chainsLocked),
      child: RiseCard(
        radius: RiseRadii.base,
        child: Row(
          children: [
            Expanded(child: Text(label, style: RiseText.body)),
            if (summary.isNotEmpty) ...[
              Text(summary, style: RiseText.caption),
              const SizedBox(width: 8),
            ],
            Icon(Icons.chevron_right, size: 20, color: RiseColors.textDim),
          ],
        ),
      ),
    );
  }

  /// The tappable "Sound" row: shows the current tone's label (or "Voice clip"
  /// for a downloaded file sound) with its category, and opens the categorized
  /// browser on tap. A downloaded voice clip is set from the Voice inbox, not
  /// here, but the row still lets the user switch to a bundled tone.
  Widget _soundRow(Alarm draft) {
    final isVoice = isFileSound(draft.soundAsset);
    final label = isVoice ? kVoiceSoundLabel : soundLabelFor(draft.soundAsset);
    final category = isVoice ? null : soundCategoryFor(draft.soundAsset);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _busy ? null : () => _openSoundPicker(draft),
      child: RiseCard(
        radius: RiseRadii.base,
        child: Row(
          children: [
            Expanded(child: Text(label, style: RiseText.body)),
            if (category != null) ...[
              Text(category.label, style: RiseText.caption),
              const SizedBox(width: 8),
            ],
            Icon(Icons.chevron_right, size: 20, color: RiseColors.textDim),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(draftProvider);
    if (draft == null) return const SizedBox.shrink();
    final isEdit = draft.id != 0;
    final use24h = ref.watch(currentSettingsProvider).use24HourTime;

    // Gating: advanced missions (typing/QR/walk/photo/eyes) and mission chains
    // (2–3) are premium. Watching the gate here keeps the entitlement stream
    // warm so the flags are resolved by the time the picker opens; a locked
    // choice inside the sheet routes to the paywall instead of selecting.
    final gate = ref.watch(premiumGateProvider);
    final missionsLocked = !gate.canUse(PremiumFeature.advancedMissions);
    final chainsLocked = !gate.canUse(PremiumFeature.missionChains);

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
              use24h: use24h,
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
          _section('Sound', _soundRow(draft)),
          _section('Wake mission',
              _missionRow(draft, missionsLocked, chainsLocked)),
          const SizedBox(height: 20),
          RiseCard(
            radius: RiseRadii.base,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Vibrate', style: RiseText.body),
                    RiseSwitch(
                      value: draft.vibrate,
                      onChanged: (v) => _update(draft.copyWith(vibrate: v)),
                    ),
                  ],
                ),
                if (draft.vibrate) ...[
                  Divider(height: 20, color: RiseColors.divider),
                  SegmentedControl<String>(
                    key: const Key('vibration-pattern-segmented'),
                    segments: const [
                      (value: 'gentle', label: 'Gentle'),
                      (value: 'standard', label: 'Standard'),
                      (value: 'intense', label: 'Intense'),
                    ],
                    // An unknown/legacy stored key renders as Standard — the
                    // same fallback the ringer applies natively.
                    selected: const ['gentle', 'standard', 'intense']
                            .contains(draft.vibrationPattern)
                        ? draft.vibrationPattern
                        : 'standard',
                    onChanged: (v) =>
                        _update(draft.copyWith(vibrationPattern: v)),
                  ),
                ],
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
