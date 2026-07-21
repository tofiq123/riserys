import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/auth/auth_service.dart';
import '../../data/backup/backup_coordinator.dart';
import '../../domain/alarm.dart';
import '../../domain/clock_format.dart';
import '../../domain/premium_feature.dart';
import '../../domain/rise_settings.dart';
import '../backup_sync_host.dart';
import '../components/rise_buttons.dart';
import '../components/rise_card.dart';
import '../components/rise_switch.dart';
import '../components/section_label.dart';
import '../components/segmented.dart';
import '../components/time_dial.dart';
import '../components/toast.dart';
import '../state/alarm_providers.dart';
import '../state/auth_providers.dart';
import '../state/backup_providers.dart';
import '../state/entitlement_providers.dart';
import '../state/settings_providers.dart';
import '../state/wake_providers.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'paywall_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final ctrl = ref.read(settingsProvider.notifier);

    // Smart wake-check and adaptive difficulty are premium. The plain wake-check
    // (re-ring) and completing any mission stay free — reliability is never
    // gated. Unconfigured/unlocked → both false, so behaviour is unchanged.
    final gate = ref.watch(premiumGateProvider);
    final smartLocked = !gate.canUse(PremiumFeature.smartWakeCheck);
    final adaptiveLocked = !gate.canUse(PremiumFeature.adaptiveDifficulty);

    return Scaffold(
      backgroundColor: RiseColors.appBg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              RiseSpacing.screen, 8, RiseSpacing.screen, 40),
          children: [
            Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).maybePop(),
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    child: Icon(Icons.arrow_back,
                        color: RiseColors.text, size: 22),
                  ),
                ),
                const SizedBox(width: 8),
                Text('Settings', style: RiseText.title),
              ],
            ),
            const SizedBox(height: 20),
            const SectionLabel('Snooze'),
            const SizedBox(height: 12),
            RiseCard(
              child: Column(
                children: [
                  _stepperRow(
                    label: 'Max snoozes',
                    value: s.snoozeMaxCount,
                    keyPrefix: 'snooze-max',
                    onDec: () => ctrl
                        .setSnoozeMaxCount((s.snoozeMaxCount - 1).clamp(0, 5)),
                    onInc: () => ctrl
                        .setSnoozeMaxCount((s.snoozeMaxCount + 1).clamp(0, 5)),
                  ),
                  Divider(height: 20, color: RiseColors.divider),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Length', style: RiseText.caption),
                  ),
                  const SizedBox(height: 8),
                  SegmentedControl<int>(
                    segments: const [
                      (value: 0, label: 'Shrinking'),
                      (value: 5, label: '5m'),
                      (value: 10, label: '10m'),
                      (value: 15, label: '15m'),
                    ],
                    selected: s.snoozeFlatMinutes,
                    onChanged: ctrl.setSnoozeFlatMinutes,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const SectionLabel('Wake-up check'),
            const SizedBox(height: 6),
            Text('If you don\'t confirm you\'re up, Rise re-rings.',
                style: RiseText.caption),
            const SizedBox(height: 12),
            RiseCard(
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Enabled', style: RiseText.body),
                      RiseSwitch(
                          key: const Key('wake-check-switch'),
                          value: s.wakeCheckEnabled,
                          onChanged: ctrl.setWakeCheckEnabled),
                    ],
                  ),
                  Divider(height: 20, color: RiseColors.divider),
                  _stepperRow(
                    label: 'Check after',
                    value: s.wakeCheckDelayMinutes,
                    suffix: 'min',
                    keyPrefix: 'wake-delay',
                    onDec: () => ctrl.setWakeCheckDelayMinutes(
                        (s.wakeCheckDelayMinutes - 1).clamp(1, 30)),
                    onInc: () => ctrl.setWakeCheckDelayMinutes(
                        (s.wakeCheckDelayMinutes + 1).clamp(1, 30)),
                  ),
                  Divider(height: 20, color: RiseColors.divider),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(child: _gatedLabel('Smart check', smartLocked)),
                      RiseSwitch(
                          key: const Key('smart-wake-check-switch'),
                          value: s.smartWakeCheck,
                          onChanged: (v) {
                            if (v && smartLocked) {
                              openPaywall(context);
                              return;
                            }
                            ctrl.setSmartWakeCheck(v);
                          }),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                        'If you\'re clearly up and moving, Rise skips the '
                        're-ring. Not sure? It gently checks in — '
                        '"Still up? Let\'s make sure."',
                        style: RiseText.caption),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const SectionLabel('Wake plan'),
            const SizedBox(height: 6),
            Text(
                'The first thing you\'ll do when the alarm rings — shown on the '
                'alarm screen as a gentle reminder.',
                style: RiseText.caption),
            const SizedBox(height: 12),
            RiseCard(child: const _WakePlanField()),
            const SizedBox(height: 24),
            const SectionLabel('Sleep goal'),
            const SizedBox(height: 6),
            Text(
                'Your steady wake time — a gentle anchor for a more consistent '
                'rhythm. Optional, and never used to change your alarms on its own.',
                style: RiseText.caption),
            const SizedBox(height: 12),
            const _SleepGoalCard(),
            const SizedBox(height: 24),
            const SectionLabel('Missions'),
            const SizedBox(height: 6),
            Text(
                'Adaptive difficulty nudges your mission one tier harder when '
                'you\'ve been breezing through it. Completing it always dismisses '
                '— it never locks you out.',
                style: RiseText.caption),
            const SizedBox(height: 12),
            RiseCard(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _gatedLabel('Adaptive difficulty', adaptiveLocked),
                  RiseSwitch(
                      key: const Key('adaptive-missions-switch'),
                      value: s.adaptiveMissions,
                      onChanged: (v) {
                        if (v && adaptiveLocked) {
                          openPaywall(context);
                          return;
                        }
                        ctrl.setAdaptiveMissions(v);
                      }),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const SectionLabel('Sensory wake'),
            const SizedBox(height: 6),
            Text(
                'A gentle on-screen sunrise while your alarm rings. A phone '
                'screen is far too dim to actually wake you — treat it as '
                'ambience, not the wake-up.',
                style: RiseText.caption),
            const SizedBox(height: 12),
            RiseCard(
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Sunrise wake', style: RiseText.body),
                      RiseSwitch(
                          key: const Key('sunrise-wake-switch'),
                          value: s.sunriseWake,
                          onChanged: ctrl.setSunriseWake),
                    ],
                  ),
                  Divider(height: 20, color: RiseColors.divider),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                          child:
                              Text('Get real light', style: RiseText.body)),
                      RiseSwitch(
                          key: const Key('real-light-prompt-switch'),
                          value: s.realLightPrompt,
                          onChanged: ctrl.setRealLightPrompt),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                        'When you wake, a brief note suggests getting real, '
                        'bright light — the thing that actually helps you feel '
                        'awake.',
                        style: RiseText.caption),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const SectionLabel('Display'),
            const SizedBox(height: 12),
            RiseCard(
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('24-hour time', style: RiseText.body),
                      RiseSwitch(
                          key: const Key('use-24h-time-switch'),
                          value: s.use24HourTime,
                          onChanged: ctrl.setUse24HourTime),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                        'Show times like 19:30 instead of 7:30 PM, everywhere '
                        'in the app.',
                        style: RiseText.caption),
                  ),
                ],
              ),
            ),
            const _AccountBackupSection(),
          ],
        ),
      ),
    );
  }

  Widget _stepperRow({
    required String label,
    required int value,
    required String keyPrefix,
    required VoidCallback onDec,
    required VoidCallback onInc,
    String? suffix,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: RiseText.body),
        Row(
          children: [
            _stepBtn(Icons.remove, ValueKey('$keyPrefix-minus'), onDec),
            SizedBox(
              width: 56,
              child: Text(suffix == null ? '$value' : '$value $suffix',
                  textAlign: TextAlign.center,
                  style: RiseText.mono(size: 15, weight: FontWeight.w600)),
            ),
            _stepBtn(Icons.add, ValueKey('$keyPrefix-plus'), onInc),
          ],
        ),
      ],
    );
  }

  /// A row label that grows a small lock glyph when the adjacent control is a
  /// premium-gated toggle. Purely a signpost — the gate itself is on the toggle.
  Widget _gatedLabel(String text, bool locked) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: Text(text, style: RiseText.body)),
          if (locked) ...[
            const SizedBox(width: 6),
            Icon(Icons.lock_outline, size: 14, color: RiseColors.textDim),
          ],
        ],
      );

  Widget _stepBtn(IconData icon, Key key, VoidCallback onTap) => GestureDetector(
        key: key,
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: RiseColors.surface2,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: RiseColors.border),
          ),
          child: Icon(icon, size: 18, color: RiseColors.textDim),
        ),
      );
}

/// The editable wake-plan (implementation intention) field. Its own stateful
/// widget so the controller is seeded once from the persisted value and
/// survives Settings rebuilds. Persists on each edit (trimmed).
class _WakePlanField extends ConsumerStatefulWidget {
  const _WakePlanField();

  @override
  ConsumerState<_WakePlanField> createState() => _WakePlanFieldState();
}

class _WakePlanFieldState extends ConsumerState<_WakePlanField> {
  late final TextEditingController _controller =
      TextEditingController(text: ref.read(settingsProvider).wakeIntention);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const Key('wake-plan-field'),
      controller: _controller,
      textCapitalization: TextCapitalization.sentences,
      cursorColor: RiseColors.primary,
      onChanged: (v) => ref.read(settingsProvider.notifier).setWakeIntention(v),
      decoration: const InputDecoration(hintText: 'Put my feet on the floor'),
    );
  }
}

/// The steady-wake-time affordance: shows the current goal (or "Not set") and
/// opens a dial to set or remove it. The goal is a gentle rhythm anchor — it is
/// never used to reschedule alarms automatically.
class _SleepGoalCard extends ConsumerWidget {
  const _SleepGoalCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final subtitle = s.hasTargetWake
        ? formatClock(s.targetWakeHour!, s.targetWakeMinute!,
            use24h: s.use24HourTime)
        : 'Not set';

    return GestureDetector(
      key: const Key('sleep-goal-card'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _showSheet(context, ref, s),
      child: RiseCard(
        child: Row(
          children: [
            Icon(Icons.wb_sunny_outlined,
                color: RiseColors.waking, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Steady wake time',
                      style:
                          RiseText.body.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: RiseText.caption.copyWith(
                          color: s.hasTargetWake
                              ? RiseColors.text
                              : RiseColors.textDim)),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                color: RiseColors.textFaint, size: 20),
          ],
        ),
      ),
    );
  }

  void _showSheet(BuildContext context, WidgetRef ref, RiseSettings s) {
    // Seed the dial from the current goal, or a sensible default (7:00 AM).
    var hour24 = s.hasTargetWake ? s.targetWakeHour! : 7;
    var minute = s.hasTargetWake ? s.targetWakeMinute! : 0;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: RiseColors.card,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setLocal) {
          final dial = (
            hour12: hour24 % 12 == 0 ? 12 : hour24 % 12,
            minute: minute,
            isAm: hour24 < 12,
          );
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(RiseSpacing.screen),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Steady wake time', style: RiseText.title),
                  const SizedBox(height: 6),
                  Text(
                      'Pick a time you\'d like to wake most days. It just guides '
                      'gentle suggestions — your alarms only change when you say so.',
                      style: RiseText.caption),
                  const SizedBox(height: 12),
                  TimeDial(
                    use24h: s.use24HourTime,
                    value: dial,
                    onChanged: (t) => setLocal(() {
                      hour24 = Alarm.to24Hour(t.hour12, t.isAm);
                      minute = t.minute;
                    }),
                  ),
                  const SizedBox(height: 16),
                  PrimaryButton(
                    key: const Key('sleep-goal-save'),
                    label: 'Save goal',
                    onPressed: () {
                      ref
                          .read(settingsProvider.notifier)
                          .setTargetWakeTime(hour24, minute);
                      Navigator.of(sheetContext).pop();
                    },
                  ),
                  if (s.hasTargetWake) ...[
                    const SizedBox(height: 8),
                    GestureDetector(
                      key: const Key('sleep-goal-remove'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        ref
                            .read(settingsProvider.notifier)
                            .clearTargetWakeTime();
                        Navigator.of(sheetContext).pop();
                      },
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        child: Text('Remove goal',
                            style: RiseText.body.copyWith(
                                color: RiseColors.textDim,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Account backup / restore. Rendered only when auth is configured AND the user
/// is signed in — otherwise it collapses to nothing, so the local-only app is
/// unchanged. v1 offers a manual "Restore from account", which (matching the
/// auto-restore) only applies when this device has no alarms yet.
class _AccountBackupSection extends ConsumerStatefulWidget {
  const _AccountBackupSection();

  @override
  ConsumerState<_AccountBackupSection> createState() =>
      _AccountBackupSectionState();
}

class _AccountBackupSectionState extends ConsumerState<_AccountBackupSection> {
  bool _restoring = false;

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(authServiceProvider) is! DisabledAuthService;
    final signedIn = ref.watch(accountProvider).value != null;
    if (!enabled || !signedIn) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const SectionLabel('Account backup'),
        const SizedBox(height: 6),
        Text(
            'Your alarms and wake history back up to your account automatically. '
            'On a new phone, sign in and they restore.',
            style: RiseText.caption),
        const SizedBox(height: 12),
        GestureDetector(
          key: const Key('restore-from-account'),
          behavior: HitTestBehavior.opaque,
          onTap: _restoring ? null : _restore,
          child: RiseCard(
            child: Row(
              children: [
                Icon(Icons.cloud_download_outlined,
                    color: RiseColors.primary, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Restore from account',
                          style: RiseText.body
                              .copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text('Only when this device has no alarms yet',
                          style: RiseText.caption
                              .copyWith(color: RiseColors.textDim)),
                    ],
                  ),
                ),
                if (_restoring)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: RiseColors.primary),
                  )
                else
                  Icon(Icons.chevron_right,
                      color: RiseColors.textFaint, size: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _restore() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: RiseColors.card,
        title: Text('Restore from account?', style: RiseText.title),
        content: Text(
            'This pulls your backed-up alarms and wake history from your '
            'account. It only restores when this device has no alarms yet.',
            style: RiseText.body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Cancel',
                style: RiseText.body.copyWith(color: RiseColors.textDim)),
          ),
          TextButton(
            key: const Key('restore-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Restore',
                style: RiseText.body.copyWith(
                    color: RiseColors.primary, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _restoring = true);
    RestoreOutcome outcome;
    try {
      final localEmpty =
          (await ref.read(alarmRepositoryProvider).all()).isEmpty;
      outcome = await ref.read(backupCoordinatorProvider).restore(
            localAlarmsEmpty: localEmpty,
            apply: (r) => writeRestoreToLocal(
              alarmRepo: ref.read(alarmRepositoryProvider),
              wakeRepo: ref.read(wakeEventRepositoryProvider),
              sync: ref.read(alarmSyncServiceProvider),
              result: r,
            ),
          );
    } catch (_) {
      outcome = RestoreOutcome.nothingToRestore;
    }
    if (!mounted) return;
    setState(() => _restoring = false);
    final (message, kind) = switch (outcome) {
      RestoreOutcome.restored => (
          'Restored your alarms and wake history from your account.',
          RiseToastKind.success
        ),
      RestoreOutcome.localNotEmpty => (
          'You already have alarms on this device.',
          RiseToastKind.info
        ),
      RestoreOutcome.nothingToRestore => (
          'No backup found for your account yet.',
          RiseToastKind.info
        ),
    };
    _snack(message, kind: kind);
  }

  void _snack(String message, {RiseToastKind kind = RiseToastKind.info}) {
    if (!mounted) return;
    RiseToast.show(context, message, kind: kind);
  }
}
