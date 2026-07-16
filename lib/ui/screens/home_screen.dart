import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/alarm.dart';
import '../../domain/scheduled_occurrence.dart';
import '../components/day_chips.dart';
import '../components/rise_buttons.dart';
import '../components/rise_card.dart';
import '../components/rise_switch.dart';
import '../components/section_label.dart';
import '../state/alarm_providers.dart';
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

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({
    super.key,
    required this.onNew,
    required this.onEdit,
    required this.onPreview,
  });

  final VoidCallback onNew;
  final void Function(Alarm) onEdit;
  final VoidCallback onPreview;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Drives the hero's live countdown.
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
    final alarmsAsync = ref.watch(alarmsProvider);
    final alarms = alarmsAsync.value ?? const <Alarm>[];
    final next = ref.watch(nextOccurrenceProvider).value;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            RiseSpacing.screen, 8, RiseSpacing.screen, 108),
        children: [
          _header(),
          const SizedBox(height: 18),
          _hero(alarms, next),
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_greeting(), style: RiseText.display),
        Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(color: RiseColors.primary, shape: BoxShape.circle),
          child: const Icon(Icons.person, color: RiseColors.primaryText, size: 20),
        ),
      ],
    );
  }

  Widget _hero(List<Alarm> alarms, ScheduledOccurrence? next) {
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

    Alarm? alarm;
    for (final a in alarms) {
      if (a.id == next.alarmId) {
        alarm = a;
        break;
      }
    }
    final hour12 = alarm?.hour12 ?? 0;
    final minute = alarm?.minute ?? 0;
    final ampm = (alarm?.isAm ?? true) ? 'AM' : 'PM';
    final remaining = next.fireAt.toLocal().difference(DateTime.now());

    return RiseCard(
      padding: const EdgeInsets.all(20),
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
                      Text('$hour12:${minute.toString().padLeft(2, '0')}',
                          style: RiseText.mono(size: 46, weight: FontWeight.w500)),
                      const SizedBox(width: 8),
                      Text(ampm, style: RiseText.mono(size: 16, color: RiseColors.textDim)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text('${next.label} · rings ',
                          style: RiseText.caption),
                      Text(_countdown(remaining),
                          style: RiseText.caption.copyWith(
                              color: RiseColors.accent, fontWeight: FontWeight.w600)),
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
                child: const Icon(Icons.notifications_active_outlined,
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
  const _AlarmRow({required this.alarm, required this.onEdit, required this.onToggle});

  final Alarm alarm;
  final VoidCallback onEdit;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
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
                        Text('${alarm.hour12}:${alarm.minute.toString().padLeft(2, '0')}',
                            style: RiseText.mono(
                                size: 27,
                                color: alarm.enabled ? RiseColors.text : RiseColors.textFaint)),
                        const SizedBox(width: 6),
                        Text(alarm.isAm ? 'AM' : 'PM',
                            style: RiseText.mono(size: 13, color: RiseColors.textDim)),
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
