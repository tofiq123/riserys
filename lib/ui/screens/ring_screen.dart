import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/alarm_sync_service.dart';
import '../../data/motion_sensor.dart';
import '../../data/native/alarm_api.g.dart';
import '../../data/snooze.dart';
import '../../domain/adaptive_difficulty.dart';
import '../../domain/alarm.dart';
import '../../domain/wake_confidence.dart';
import '../../domain/wake_event.dart';
import '../components/slide_to_wake.dart';
import '../state/alarm_providers.dart';
import '../state/settings_providers.dart';
import '../state/wake_providers.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Builds the dismissal gate for a missioned alarm. Task 10 supplies the real
/// mission widgets; [onSolved] must be called exactly once when the user
/// completes the mission — that dismisses the alarm. [onAlertness], when the
/// mission produces one, reports a 0–100 alertness score (only the PVT mission
/// does); every other mission ignores it, so behavior is unchanged.
typedef MissionBuilder = Widget Function(BuildContext context, Alarm alarm,
    VoidCallback onSolved, void Function(int alertnessScore)? onAlertness);

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

/// Decides the opt-in smart wake-check outcome: is the post-dismissal stay-up
/// check satisfied, or do we fall back to the ordinary wake-check re-ring?
/// Injectable for tests; the default is [defaultStayUpDecision].
typedef StayUpDecider = Future<WakeChallengeDecision> Function(
    Alarm alarm, Duration window, int? alertnessScore);

/// DEVICE-ONLY default for the smart wake-check (Phase 11), used only when the
/// user opts in. Best-effort: senses sustained motion over [window] via the
/// pedometer, fuses it with the dismissal's [alertnessScore], and returns the
/// challenge decision. Any failure — or simply no clear "they got up" signal —
/// resolves to [WakeChallengeDecision.reCheck], the safe fall-back to a re-ring.
///
/// App-interaction sensing is not wired here (treated as false, the
/// conservative default), so today motion + alertness drive the decision; the
/// fusion already accepts it for a later device wiring.
Future<WakeChallengeDecision> defaultStayUpDecision(
    Alarm alarm, Duration window, int? alertnessScore) async {
  var sustained = false;
  try {
    sustained = await const MotionSensor().sensedSustainedMotion(window);
  } catch (_) {
    sustained = false; // unknown → conservative
  }
  return wakeChallengeDecision(
    sustainedMotion: sustained,
    appInteracted: false,
    alertnessScore: alertnessScore,
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
    this.stayUpDecision = defaultStayUpDecision,
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

  /// Decides the smart stay-up outcome when the smart wake-check setting is on.
  /// Injectable for tests; defaults to [defaultStayUpDecision] (device-only
  /// motion sensing). Never consulted when smart wake-check is off, so the
  /// default path is byte-for-byte unchanged.
  final StayUpDecider stayUpDecision;

  @override
  ConsumerState<RingScreen> createState() => _RingScreenState();
}

class _RingScreenState extends ConsumerState<RingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  Timer? _clock;
  bool _dismissing = false;
  int _attempt = 0; // bumped on a failed dismissal to reset the slider
  int _completions = 0; // missions solved so far in a chain (missionCount > 1)

  /// The alertness score reported by the mission (PVT only), captured here so
  /// [_dismiss] can persist it. null = the mission produced no score.
  int? _pendingAlertness;

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
            .finalizeDismiss(widget.alarmId,
                method: method, alertnessScore: _pendingAlertness);
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
          final delay = Duration(minutes: settings.wakeCheckDelayMinutes);
          if (settings.smartWakeCheck) {
            // Opt-in smart path: sense over the window, then arm the re-ring
            // ONLY if confidence is low/unknown. Detached so the ring screen
            // closes immediately (the sensing outlives it); best-effort.
            unawaited(_runSmartStayUp(alarm, delay, _pendingAlertness));
          } else {
            // Default path — unchanged: arm the native wake-check now.
            try {
              await widget.armWakeCheck(alarm, delay);
            } catch (e) {
              debugPrint(
                  'Rise: wake-check schedule failed for ${widget.alarmId}: $e');
            }
          }
        }
      }
    }
    if (!mounted) return;
    widget.onDismissed?.call();
  }

  /// The opt-in smart stay-up check. Best-effort and detached from the ring
  /// screen's lifecycle (it may outlive the popped screen): it senses over the
  /// window and, ONLY if confidence is low or unknown, arms the ordinary
  /// wake-check re-ring — the exact same [armWakeCheck] path as today. It never
  /// suppresses a needed re-ring: any sensing error defaults to re-check. Uses
  /// only the injected callbacks (no `ref`/`context`), so it is safe post-dispose.
  Future<void> _runSmartStayUp(
      Alarm alarm, Duration delay, int? alertness) async {
    WakeChallengeDecision decision;
    try {
      decision = await widget.stayUpDecision(alarm, delay, alertness);
    } catch (e) {
      debugPrint('Rise: smart stay-up sense failed for ${alarm.id}: $e');
      decision = WakeChallengeDecision.reCheck; // conservative
    }
    if (decision == WakeChallengeDecision.reCheck) {
      try {
        await widget.armWakeCheck(alarm, delay);
      } catch (e) {
        debugPrint('Rise: wake-check schedule failed for ${alarm.id}: $e');
      }
    }
  }

  /// One mission in a chain was completed. Dismisses once [missionCount]
  /// completions are reached; otherwise rebuilds a fresh mission instance (the
  /// bumped `_completions` changes the gate's key, resetting it) for the next
  /// rep. The anti-trap invariant holds: reaching the count always dismisses,
  /// and nothing but the count gates dismissal. A PVT chain keeps the last
  /// reported alertness score, since `_pendingAlertness` survives the rebuild.
  void _onMissionSolved(int missionCount) {
    if (_dismissing) return; // a dismiss is already in flight
    if (_completions + 1 >= missionCount) {
      _dismiss('mission');
    } else {
      setState(() => _completions++);
    }
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

  /// A gentle nudge showing the user's own wake plan (their implementation
  /// intention). Never a demand — just the concrete first move they chose.
  Widget _planReminder(String intention) => Container(
        constraints: const BoxConstraints(maxWidth: 340),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: RiseColors.accentSoft,
          borderRadius: BorderRadius.circular(RiseRadii.base),
          border: Border.all(color: RiseColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.flag_outlined,
                size: 16, color: RiseColors.accent),
            const SizedBox(width: 8),
            Flexible(
              child: Text('Your plan: $intention',
                  textAlign: TextAlign.center,
                  style: RiseText.body
                      .copyWith(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );

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
    final events = ref.watch(wakeEventsProvider).value ?? const <WakeEvent>[];
    final snoozeCount = events
            .firstWhereOrNull((e) => e.alarmId == widget.alarmId && e.isOpen)
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

    final isMissioned = alarm != null &&
        alarm.mission != 'none' &&
        widget.missionBuilder != null;
    final missionCount = alarm?.missionCount ?? 1;
    final gate = KeyedSubtree(
      // Both counters bump the key so a fresh mission instance is built: a
      // failed dismissal resets the current rep, a completion advances the chain.
      key: ValueKey('$_attempt-$_completions'),
      child: isMissioned
          ? widget.missionBuilder!(
              context,
              // When adaptive difficulty is opt-in ON, a breezing user is shown
              // one tier harder — a suggestion only; completing it still
              // dismisses. Off (default): the chosen difficulty is used as-is.
              settings.adaptiveMissions
                  ? alarm.copyWith(
                      missionDiff:
                          adaptiveDifficulty(alarm.missionDiff, events))
                  : alarm,
              () => _onMissionSolved(missionCount),
              (score) => _pendingAlertness = score)
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
              if (settings.wakeIntention.isNotEmpty) ...[
                const SizedBox(height: 18),
                _planReminder(settings.wakeIntention),
              ],
              const Spacer(),
              if (isMissioned && missionCount > 1) ...[
                Text('${_completions + 1} of $missionCount',
                    style: RiseText.mono(
                        size: 14, color: RiseColors.textDim)),
                const SizedBox(height: 12),
              ],
              gate,
              if (canSnooze) _snoozeButton(snoozeMinutes),
            ],
          ),
        ),
      ),
    );
  }
}
