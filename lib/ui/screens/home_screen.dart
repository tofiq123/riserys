import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/alarm.dart';
import '../../domain/clock_format.dart';
import '../../domain/scheduled_occurrence.dart';
import '../../domain/wake_shift.dart';
import '../components/day_chips.dart';
import '../components/rise_buttons.dart';
import '../components/rise_card.dart';
import '../components/rise_switch.dart';
import '../components/section_label.dart';
import '../components/toast.dart';
import '../state/alarm_providers.dart';
import '../state/settings_providers.dart';
import '../state/wake_providers.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

String _greeting() {
  final h = DateTime.now().hour;
  if (h < 12) return 'Good morning';
  if (h < 18) return 'Good afternoon';
  return 'Good evening';
}

String _countdown(Duration d) {
  if (d.isNegative || d.inSeconds == 0) return 'now';
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  if (h > 0) return 'in ${h}h ${m}m';
  return 'in ${m}m ${s.toString().padLeft(2, '0')}s';
}

/// The hero's live "rings in …" label. Owns its OWN one-second ticker so only
/// this text repaints each second — the rest of Home (header, streak pill, the
/// whole alarm list) rebuilds only on real data changes, and nothing ticks while
/// Home is occluded by the editor overlay.
class _HeroCountdown extends StatefulWidget {
  const _HeroCountdown({required this.fireAt});

  /// The next fire instant; the countdown runs to its local time.
  final DateTime fireAt;

  @override
  State<_HeroCountdown> createState() => _HeroCountdownState();
}

class _HeroCountdownState extends State<_HeroCountdown> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.fireAt.toLocal().difference(DateTime.now());
    return Text(_countdown(remaining),
        style: RiseText.caption
            .copyWith(color: RiseColors.accent, fontWeight: FontWeight.w600));
  }
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({
    super.key,
    required this.onNew,
    required this.onEdit,
    required this.onPreview,
    this.onStreak,
    this.onProfile,
  });

  final VoidCallback onNew;
  final void Function(Alarm) onEdit;
  final VoidCallback onPreview;

  /// Opens Stats (the app shell switches tab). Null leaves the pill inert.
  final VoidCallback? onStreak;

  /// Opens Profile (the app shell switches tab). Null leaves the avatar inert.
  final VoidCallback? onProfile;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  // No screen-level ticker: only the hero countdown changes each second, and it
  // owns its own timer (see _HeroCountdown). This screen rebuilds only on real
  // data/settings changes — not 60×/min, and not while occluded by the editor.

  @override
  Widget build(BuildContext context) {
    final alarmsAsync = ref.watch(alarmsProvider);
    final alarms = alarmsAsync.value ?? const <Alarm>[];
    final next = ref.watch(nextOccurrenceProvider).value;
    final use24h =
        ref.watch(currentSettingsProvider.select((s) => s.use24HourTime));

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            RiseSpacing.screen, 8, RiseSpacing.screen, 108),
        children: [
          _header(),
          const SizedBox(height: 18),
          _hero(next),
          const _ShiftSuggestion(),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SectionLabel('Your alarms'),
              GhostButton(label: '+ New', onPressed: widget.onNew),
            ],
          ),
          const SizedBox(height: 12),
          if (alarms.isEmpty)
            _empty()
          else
            for (final a in alarms) ...[
              _AlarmRow(
                alarm: a,
                use24h: use24h,
                onEdit: () => widget.onEdit(a),
                onToggle: (v) =>
                    ref.read(alarmMutationsProvider).setEnabled(a.id, v),
              ),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }

  Widget _header() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: Text(_greeting(),
              style: RiseText.display, overflow: TextOverflow.ellipsis),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _streakPill(),
            const SizedBox(width: 10),
            Semantics(
              button: true,
              label: 'Profile',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onProfile,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: RiseColors.primary, shape: BoxShape.circle),
                  child: Icon(Icons.person,
                      color: RiseColors.primaryText, size: 20),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _streakPill() {
    final streak = ref.watch(streakProvider);
    final has = streak.current > 0;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onStreak,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: has ? RiseColors.accentSoft : RiseColors.surface2,
          borderRadius: BorderRadius.circular(RiseRadii.pill),
          border: Border.all(color: RiseColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_fire_department,
                size: 16,
                color: has ? RiseColors.waking : RiseColors.textFaint),
            const SizedBox(width: 5),
            Text(has ? '${streak.current}' : 'Start',
                style: RiseText.mono(
                    size: 14,
                    weight: FontWeight.w700,
                    color: has ? RiseColors.text : RiseColors.textDim)),
          ],
        ),
      ),
    );
  }

  Widget _hero(ScheduledOccurrence? next) {
    if (next == null) {
      return RiseCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('Next alarm'),
              const SizedBox(height: 10),
              Text('No alarm set',
                  style: RiseText.mono(size: 24, color: RiseColors.textFaint)),
            ],
          ),
        ),
      );
    }

    final use24h =
        ref.watch(currentSettingsProvider.select((s) => s.use24HourTime));
    final parts = formatClockParts(next.hour, next.minute, use24h: use24h);

    return RiseCard(
      padding: const EdgeInsets.all(RiseSpacing.screen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionLabel('Next alarm'),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text('${parts.hour}:${parts.minute}',
                          style: RiseText.mono(size: 46, weight: FontWeight.w500)),
                      if (parts.period.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(parts.period,
                            style: RiseText.mono(size: 16, color: RiseColors.textDim)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text('${next.label} · rings ',
                          style: RiseText.caption),
                      _HeroCountdown(fireAt: next.fireAt),
                    ],
                  ),
                ],
              ),
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: RiseColors.accentSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.notifications_active_outlined,
                    color: RiseColors.accent, size: 22),
              ),
            ],
          ),
          const SizedBox(height: 16),
          PrimaryButton(
              label: 'Preview alarm', icon: Icons.play_arrow, onPressed: widget.onPreview),
        ],
      ),
    );
  }

  Widget _empty() {
    return RiseCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: Text('No alarms yet. Tap New to set one.',
              style: RiseText.caption),
        ),
      ),
    );
  }
}

class _AlarmRow extends StatelessWidget {
  const _AlarmRow({
    required this.alarm,
    required this.use24h,
    required this.onEdit,
    required this.onToggle,
  });

  final Alarm alarm;
  final bool use24h;
  final VoidCallback onEdit;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final parts = formatClockParts(alarm.hour, alarm.minute, use24h: use24h);
    return Opacity(
      opacity: alarm.enabled ? 1 : 0.62,
      child: RiseCard(
        radius: RiseRadii.base,
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onEdit,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text('${parts.hour}:${parts.minute}',
                            style: RiseText.mono(
                                size: 27,
                                color: alarm.enabled ? RiseColors.text : RiseColors.textFaint)),
                        if (parts.period.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Text(parts.period,
                              style: RiseText.mono(size: 13, color: RiseColors.textDim)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text('${alarm.label} · ${repeatLabel(alarm.days)}',
                        style: RiseText.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 9),
                    DayChips(days: alarm.days, compact: true),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            RiseSwitch(value: alarm.enabled, onChanged: onToggle),
          ],
        ),
      ),
    );
  }
}

/// A gentle, opt-in nudge toward the user's steady wake time (their "Sleep
/// goal"). Only appears when a goal is set and the next alarm differs from it.
/// Proposes moving that alarm ONE small step toward the goal — the user must
/// tap to apply. Alarms are never rescheduled automatically: a silent shift to
/// an earlier time could cause a missed wake, which is a clinical red line.
class _ShiftSuggestion extends ConsumerWidget {
  const _ShiftSuggestion();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // currentSettingsProvider is the resilient reader — defaults (no goal) when
    // the settings store is unavailable, so this never throws on Home.
    final settings = ref.watch(currentSettingsProvider);
    if (!settings.hasTargetWake) return const SizedBox.shrink();

    final next = ref.watch(nextOccurrenceProvider).value;
    if (next == null) return const SizedBox.shrink();

    final alarms = ref.watch(alarmsProvider).value ?? const <Alarm>[];
    Alarm? alarm;
    for (final a in alarms) {
      if (a.id == next.alarmId) {
        alarm = a;
        break;
      }
    }
    if (alarm == null) return const SizedBox.shrink();

    final goalH = settings.targetWakeHour!;
    final goalM = settings.targetWakeMinute!;
    // Already at the goal — nothing to suggest.
    if (alarm.hour == goalH && alarm.minute == goalM) {
      return const SizedBox.shrink();
    }

    final shifted = nextShiftedWakeTime(
      fromHour: alarm.hour,
      fromMinute: alarm.minute,
      goalHour: goalH,
      goalMinute: goalM,
    );
    if (shifted.hour == alarm.hour && shifted.minute == alarm.minute) {
      return const SizedBox.shrink();
    }

    final label = alarm.label.isNotEmpty ? alarm.label : 'your alarm';
    final targetAlarm = alarm;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: RiseCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.wb_twilight_outlined,
                    color: RiseColors.waking, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Shift toward your goal',
                      style:
                          RiseText.body.copyWith(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
                'Your steady wake time is '
                '${formatClock(goalH, goalM, use24h: settings.use24HourTime)}. '
                'Move "$label" from '
                '${formatClock(targetAlarm.hour, targetAlarm.minute, use24h: settings.use24HourTime)} '
                'to ${formatShift(shifted, use24h: settings.use24HourTime)}?',
                style: RiseText.caption),
            const SizedBox(height: 12),
            PrimaryButton(
              label:
                  'Shift to ${formatShift(shifted, use24h: settings.use24HourTime)}',
              icon: Icons.arrow_forward,
              onPressed: () => _apply(context, ref, targetAlarm, shifted),
            ),
          ],
        ),
      ),
    );
  }

  void _apply(BuildContext context, WidgetRef ref, Alarm alarm,
      ({int hour, int minute}) shifted) {
    final use24h = ref.read(currentSettingsProvider).use24HourTime;
    // Editing the time clears any stale dismissal so the new occurrence rings.
    ref.read(alarmMutationsProvider).save(alarm.copyWith(
          hour: shifted.hour,
          minute: shifted.minute,
          clearLastDismissedAt: true,
        ));
    // Fires into the root overlay, so it survives this suggestion card vanishing
    // once the alarm is shifted (the card's `shifted == alarm` guard hides it).
    RiseToast.show(context, 'Moved to ${formatShift(shifted, use24h: use24h)}');
  }
}
