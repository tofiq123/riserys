import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../components/rise_card.dart';
import '../components/rise_switch.dart';
import '../components/section_label.dart';
import '../components/segmented.dart';
import '../state/settings_providers.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final ctrl = ref.read(settingsProvider.notifier);

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
                  child: const Padding(
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
                  const Divider(height: 20, color: RiseColors.divider),
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
                          value: s.wakeCheckEnabled,
                          onChanged: ctrl.setWakeCheckEnabled),
                    ],
                  ),
                  const Divider(height: 20, color: RiseColors.divider),
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
