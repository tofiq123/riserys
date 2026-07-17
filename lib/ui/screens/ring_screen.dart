import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/alarm_sync_service.dart';
import '../../data/native/alarm_api.g.dart';
import '../../data/snooze.dart';
import '../../domain/alarm.dart';
import '../components/slide_to_wake.dart';
import '../state/alarm_providers.dart';
import '../state/settings_providers.dart';
import '../state/wake_providers.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Builds the dismissal gate for a missioned alarm. Task 10 supplies the real
/// mission widgets; [onSolved] must be called exactly once when the user
/// completes the mission — that dismisses the alarm.
typedef MissionBuilder = Widget Function(
    BuildContext context, Alarm alarm, VoidCallback onSolved);

/// Fully dismisses a ringing alarm. The order is deliberate and load-bearing
/// (validated on a physical device in Plan 1):
///
/// 1. [AlarmHostApi.stopRinging] runs FIRST and unconditionally — a user who
///    dismisses must get silence immediately, never gated on a database write
///    that can block for seconds under SQLite contention. It talks straight to
///    the native side and does not depend on the Dart service being configured,
///    so a ringing alarm is always stoppable.
/// 2. Recording the dismissal + reconciling is best-effort and MUST run after
///    stopRinging: it disables a fired one-shot so reconcile does not re-arm it
///    for tomorrow. A failure here is logged, not fatal — the alarm is already
///    silent.
///
/// If stopRinging itself throws (a real platform failure — the alarm may still
/// be sounding), the throw propagates so the caller keeps the ring screen up
/// for a retry instead of falsely reporting success.
Future<void> dismissRingingAlarm(int alarmId) async {
  await AlarmHostApi().stopRinging(alarmId);
  try {
    await AlarmSyncService.instance.repository
        .recordDismissed(alarmId, DateTime.now().toUtc());
    await AlarmSyncService.instance.reconcileNow();
  } catch (e) {
    debugPrint('Rise: could not record dismissal for alarm $alarmId: $e');
  }
}

/// Arms the post-dismissal wake-up check for [alarm] at now + [delay]. The
/// re-fire time (checkAt + 100s) is computed natively, so [NativeAlarm.fireAtEpochMs]
/// is unused here; the label/sound/vibrate carry so the re-fire rings correctly.
Future<void> defaultArmWakeCheck(Alarm alarm, Duration delay) async {
  final checkAt = DateTime.now().toUtc().add(delay).millisecondsSinceEpoch;
  await AlarmHostApi().scheduleWakeCheck(
    NativeAlarm(
      id: alarm.id,
      fireAtEpochMs: 0,
      label: alarm.label,
      soundAsset: alarm.soundAsset,
      vibrate: alarm.vibrate,
      hour: alarm.hour,
      minute: alarm.minute,
      weekdays: alarm.days.toList(),
    ),
    checkAt,
  );
}

class RingScreen extends ConsumerStatefulWidget {
  const RingScreen({
    super.key,
    required this.alarmId,
    this.onDismissed,
    this.dismissAlarm = dismissRingingAlarm,
    this.missionBuilder,
    this.record = false,
    this.snooze = snoozeAlarm,
    this.armWakeCheck = defaultArmWakeCheck,
  });

  final int alarmId;

  /// Called after the alarm is fully dismissed — the host pops the screen.
  final VoidCallback? onDismissed;

  /// The dismissal work (stop → record → reconcile). Injectable for tests;
  /// defaults to [dismissRingingAlarm].
  final Future<void> Function(int alarmId) dismissAlarm;

  final MissionBuilder? missionBuilder;

  /// When true, this firing is logged to the wake-event store — opened on
  /// mount, finalised on dismiss. Off for previews. Best-effort: a wake-log
  /// failure is logged, never thrown into the ring.
  final bool record;

  /// Snooze action (silence + defer). Injectable for tests; defaults to
  /// [snoozeAlarm].
  final Future<void> Function(int alarmId, Duration duration) snooze;

  /// Arms the "still up?" check after a real dismissal. Injectable for tests;
  /// defaults to [defaultArmWakeCheck].
  final Future<void> Function(Alarm alarm, Duration delay) armWakeCheck;

  @override
  ConsumerState<RingScreen> createState() => _RingScreenState();
}

class _RingScreenState extends ConsumerState<RingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  Timer? _clock;
  bool _dismissing = false;
  int _attempt = 0; // bumped on a failed dismissal to reset the slider

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.92,
      upperBound: 1.08,
    )..repeat(reverse: true);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {}); // advances the live clock
    });
    if (widget.record) _recordRingStart();
  }

  @override
  void dispose() {
    _clock?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _recordRingStart() async {
    try {
      await ref.read(wakeRecorderProvider).openRing(widget.alarmId);
    } catch (e) {
      debugPrint('Rise: wake-open failed for ${widget.alarmId}: $e');
    }
  }

  Future<void> _dismiss(String method) async {
    if (_dismissing) return; // guard double-taps / repeated slide fires
    setState(() => _dismissing = true);
    try {
      await widget.dismissAlarm(widget.alarmId);
    } catch (e) {
      debugPrint('Rise: dismiss failed for ${widget.alarmId}: $e');
      if (mounted) {
        setState(() {
          _dismissing = false;
          _attempt++; // fresh key resets the slide-to-wake so it can fire again
        });
      }
      return;
    }
    if (widget.record) {
      try {
        await ref
            .read(wakeRecorderProvider)
            .finalizeDismiss(widget.alarmId, method: method);
      } catch (e) {
        debugPrint('Rise: wake-finalize failed for ${widget.alarmId}: $e');
      }
      final settings = ref.read(currentSettingsProvider);
      if (settings.wakeCheckEnabled) {
        final alarm = ref
            .read(alarmsProvider)
            .value
            ?.firstWhereOrNull((a) => a.id == widget.alarmId);
        if (alarm != null) {
          try {
            await widget.armWakeCheck(
                alarm, Duration(minutes: settings.wakeCheckDelayMinutes));
          } catch (e) {
            debugPrint('Rise: wake-check schedule failed for ${widget.alarmId}: $e');
          }
        }
      }
    }
    if (!mounted) return;
    widget.onDismissed?.call();
  }

  Future<void> _snooze(Duration d) async {
    if (_dismissing) return; // shares the dismiss guard
    setState(() => _dismissing = true);
    try {
      await widget.snooze(widget.alarmId, d);
    } catch (e) {
      debugPrint('Rise: snooze failed for ${widget.alarmId}: $e');
      if (mounted) {
        setState(() {
          _dismissing = false;
          _attempt++;
        });
      }
      return;
    }
    if (!mounted) return;
    widget.onDismissed?.call(); // close the ring screen
  }

  Widget _snoozeButton(int minutes) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _snooze(Duration(minutes: minutes)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text('Snooze $minutes min',
              style: RiseText.body.copyWith(
                  color: RiseColors.textDim, fontWeight: FontWeight.w600)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final alarm = ref
        .watch(alarmsProvider)
        .value
        ?.firstWhereOrNull((a) => a.id == widget.alarmId);
    final settings = ref.watch(currentSettingsProvider);
    final snoozeCount = ref
            .watch(wakeEventsProvider)
            .value
            ?.firstWhereOrNull((e) => e.alarmId == widget.alarmId && e.isOpen)
            ?.snoozeCount ??
        0;
    final canSnooze = snoozeCount < settings.snoozeMaxCount;
    final snoozeMinutes = settings.snoozeDurationMinutes(snoozeCount);
    final label = alarm?.label ?? 'Alarm';
    final now = DateTime.now();
    final hour12 = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final ampm = now.hour < 12 ? 'AM' : 'PM';
    final reduce = MediaQuery.of(context).disableAnimations;

    Widget bell = Container(
      width: 92,
      height: 92,
      decoration: BoxDecoration(
        color: RiseColors.accentSoft,
        borderRadius: BorderRadius.circular(28),
      ),
      child: const Icon(Icons.notifications_active,
          color: RiseColors.accent, size: 44),
    );
    if (!reduce) bell = ScaleTransition(scale: _pulse, child: bell);

    final gate = KeyedSubtree(
      key: ValueKey(_attempt),
      child: (alarm != null &&
              alarm.mission != 'none' &&
              widget.missionBuilder != null)
          ? widget.missionBuilder!(context, alarm, () => _dismiss('mission'))
          : SlideToWake(onWake: () => _dismiss('slide')),
    );

    return Scaffold(
      backgroundColor: RiseColors.appBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(RiseSpacing.screen),
          child: Column(
            children: [
              const Spacer(),
              bell,
              const SizedBox(height: 30),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('$hour12:${now.minute.toString().padLeft(2, '0')}',
                      style: RiseText.mono(size: 72, weight: FontWeight.w500)),
                  const SizedBox(width: 10),
                  Text(ampm,
                      style: RiseText.mono(size: 20, color: RiseColors.textDim)),
                ],
              ),
              const SizedBox(height: 10),
              Text(label, style: RiseText.title.copyWith(color: RiseColors.textDim)),
              const Spacer(),
              gate,
              if (canSnooze) _snoozeButton(snoozeMinutes),
            ],
          ),
        ),
      ),
    );
  }
}
