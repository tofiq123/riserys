import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/alarm_sync_service.dart';
import '../../data/motion_sensor.dart';
import '../../data/native/alarm_api.g.dart';
import '../../data/nudge/nudge_service.dart';
import '../../data/ring_audio.dart';
import '../../data/screen_brightness_controller.dart';
import '../../data/snooze.dart';
import '../../domain/adaptive_difficulty.dart';
import '../../domain/alarm.dart';
import '../../domain/clock_format.dart';
import '../../domain/wake_confidence.dart';
import '../../domain/wake_event.dart';
import '../components/slide_to_wake.dart';
import '../components/toast.dart';
import '../state/alarm_providers.dart';
import '../state/crew_providers.dart';
import '../state/nudge_providers.dart';
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

/// Peeks the next alarm queued behind the one currently ringing.
Future<int?> defaultGetQueuedAlarmId() => AlarmHostApi().getQueuedAlarmId();

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
      vibrationPattern: alarm.vibrationPattern,
      hour: alarm.hour,
      minute: alarm.minute,
      weekdays: alarm.days.toList(),
    ),
    checkAt,
  );
}

/// Cancels the pending native wake-check (notification + re-fire) for
/// [alarmId]. Used by the opt-in smart wake-check once it is confident the
/// user stayed up: the check is armed unconditionally at dismissal, so
/// cancelling is the only thing "confident" changes.
Future<void> defaultCancelWakeCheck(int alarmId) =>
    AlarmHostApi().cancelWakeCheck(alarmId);

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

/// The floor of the sunrise brightness ramp — brightness starts here and rises
/// to full as dawn progresses. Not 0, so a night-dimmed phone still lifts
/// immediately when the alarm fires.
const double _minSunriseBrightness = 0.6;

/// The opt-in sunrise wake background. Maps dawn progress [t] (0 → 1) to a
/// vertical gradient that arcs from a deep pre-dawn sky at the top, through warm
/// amber, to soft daylight. Deliberately keeps the lower two-thirds — where the
/// clock, mission and dismiss controls live — warm and light at *every* t, so
/// the near-black ring UI stays fully legible: only the top sky (behind the
/// upper spacer/bell, where there is no text) carries the night → day swing.
/// Purely visual.
LinearGradient sunriseGradient(double t) {
  final p = t.clamp(0.0, 1.0);
  Color mix(Color night, Color day) => Color.lerp(night, day, p)!;
  return LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    stops: const [0.0, 0.22, 0.45, 1.0],
    colors: [
      mix(const Color(0xFF10152E), const Color(0xFFCFE0F5)), // top sky: night→day
      mix(const Color(0xFF3E325F), const Color(0xFFF8DCAB)), // upper: dusk→amber
      mix(const Color(0xFFF4DBB8), const Color(0xFFFBF2E4)), // clock band: light
      mix(const Color(0xFFF1CBA0), const Color(0xFFF8F2EA)), // ground: light
    ],
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
    this.cancelWakeCheck = defaultCancelWakeCheck,
    this.stayUpDecision = defaultStayUpDecision,
    this.brightness = const ScreenBrightnessController(),
    this.getQueuedAlarmId = defaultGetQueuedAlarmId,
    this.ringAudio,
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

  /// Cancels an armed wake-check once the smart stay-up check is confident the
  /// user got up. Injectable for tests; defaults to [defaultCancelWakeCheck].
  /// Only ever called on the opt-in smart path, and only on a confident
  /// decision — never on the default path.
  final Future<void> Function(int alarmId) cancelWakeCheck;

  /// Decides the smart stay-up outcome when the smart wake-check setting is on.
  /// Injectable for tests; defaults to [defaultStayUpDecision] (device-only
  /// motion sensing). Never consulted when smart wake-check is off, so the
  /// default path is byte-for-byte unchanged.
  final StayUpDecider stayUpDecision;

  /// The device-brightness seam for the opt-in sunrise wake. Injectable for
  /// tests (which pass a fake); defaults to the real `screen_brightness`-backed
  /// controller. Only ever touched when the sunrise setting is on, and every
  /// call is best-effort, so a plugin failure can never crash or block the ring.
  final BrightnessController brightness;

  /// The alarm waiting behind this one, if any. Injectable for tests;
  /// defaults to [defaultGetQueuedAlarmId]. Polled, not pushed — see the
  /// Pigeon doc comment on `getQueuedAlarmId`.
  final Future<int?> Function() getQueuedAlarmId;

  /// Plays the alarm tone from inside the app. Null (the default) resolves to
  /// [defaultRingAudio] — a real player on iOS, a no-op on Android, where the
  /// native `AlarmService` is already making the noise. Tests pass a
  /// [FakeRingAudio] so no widget test opens an audio device.
  final RingAudio? ringAudio;

  @override
  ConsumerState<RingScreen> createState() => _RingScreenState();
}

class _RingScreenState extends ConsumerState<RingScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulse;

  /// Drives the opt-in sunrise wake: a slow 0 → 1 dawn progress over ~45s that
  /// both paints the gradient background and ramps device brightness. Created
  /// unconditionally (cheap), started only when the sunrise setting is on.
  late final AnimationController _sunrise;
  bool _sunriseActive = false; // sunrise setting was on at mount → show + ramp
  bool _sunriseStarted = false; // one-shot guard for didChangeDependencies
  bool _pulseStarted = false; // one-shot guard for starting the bell pulse
  double _lastBrightness = -1; // last value pushed to the platform (throttle)

  Timer? _clock;
  bool _dismissing = false;
  int _attempt = 0; // bumped on a failed dismissal to reset the slider
  int _completions = 0; // missions solved so far in a chain (missionCount > 1)
  bool _lightPromptDismissed = false; // user hid the "get real light" note

  /// The alertness score reported by the mission (PVT only), captured here so
  /// [_dismiss] can persist it. null = the mission produced no score.
  int? _pendingAlertness;

  /// Seconds the alarm has been ringing — drives the auto-SOS threshold.
  int _elapsedSec = 0;

  /// One-shot guard: the crew SOS (manual or auto) has fired this ring.
  bool _sosSent = false;

  /// The alarm queued behind this one, if any — polled, not pushed.
  int? _queuedAlarmId;

  /// The in-app tone player (iOS; a no-op on Android — see [RingAudio]).
  late final RingAudio _ringAudio = widget.ringAudio ?? defaultRingAudio();

  /// One-shot guard: the tone starts the first build in which the alarm has
  /// actually loaded, since its chosen sound is only known from the record.
  bool _audioStarted = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.92,
      upperBound: 1.08,
    ); // started in didChangeDependencies, only when animations are enabled
    _sunrise = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 45),
    );
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsedSec++); // advances the live clock + auto-SOS timer
      _maybeAutoSos();
      _pollQueuedAlarm();
    });
    if (widget.record) _recordRingStart();
    _pollQueuedAlarm();
  }

  /// A thrown PlatformException must not go unhandled here, or a single
  /// failed poll would crash the ring screen — the chip is a nice-to-have,
  /// never load-bearing for dismissing the alarm.
  Future<void> _pollQueuedAlarm() async {
    int? id;
    try {
      id = await widget.getQueuedAlarmId();
    } catch (e) {
      debugPrint('Rise: could not check for a queued alarm: $e');
      return;
    }
    if (!mounted || id == _queuedAlarmId) return;
    setState(() => _queuedAlarmId = id);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Start the bell pulse only when animations are enabled — under reduce-motion
    // the bell is rendered static (see build), so a repeating controller would
    // just tick every frame with no listener. Guarded to start once.
    if (!_pulseStarted) {
      _pulseStarted = true;
      if (!MediaQuery.of(context).disableAnimations) {
        _pulse.repeat(reverse: true);
      }
    }
    // Start the sunrise once, here, where MediaQuery is available. Guarded so a
    // later dependency change never restarts or re-boosts it.
    if (_sunriseStarted) return;
    _sunriseStarted = true;
    if (!ref.read(currentSettingsProvider).sunriseWake) return;
    _sunriseActive = true;
    if (MediaQuery.of(context).disableAnimations) {
      // Respect reduce-motion: no animation. Jump to soft daylight and brighten
      // once (a static boost, not a ramp).
      _sunrise.value = 1.0;
      widget.brightness.setBrightness(1.0);
    } else {
      _sunrise.addListener(_pushBrightness);
      _sunrise.forward(); // dawn → daylight over ~45s, ramping brightness with it
    }
  }

  /// Maps the sunrise progress to a gentle brightness ramp (from
  /// [_minSunriseBrightness] up to full), pushing to the platform only on ~5%
  /// changes so we never spam the channel every animation frame. Best-effort via
  /// the injected controller.
  void _pushBrightness() {
    final target =
        _minSunriseBrightness + (1.0 - _minSunriseBrightness) * _sunrise.value;
    final stepped = (target * 20).roundToDouble() / 20; // 5% granularity
    if (stepped == _lastBrightness) return;
    _lastBrightness = stepped;
    widget.brightness.setBrightness(stepped);
  }

  @override
  void dispose() {
    _clock?.cancel();
    // Backstop: dismiss/snooze already stop the tone up front so silence is
    // immediate. This covers the screen going away by any other route.
    unawaited(_ringAudio.stop());
    _pulse.dispose();
    if (_sunriseActive) {
      // Undo the ramp: restore the system brightness on dismiss/snooze/dispose.
      _sunrise.removeListener(_pushBrightness);
      widget.brightness.restore();
    }
    _sunrise.dispose();
    super.dispose();
  }

  Future<void> _recordRingStart() async {
    try {
      await ref.read(wakeRecorderProvider).openRing(widget.alarmId);
    } catch (e) {
      debugPrint('Rise: wake-open failed for ${widget.alarmId}: $e');
    }
  }

  /// After the alarm has rung unanswered for [_autoSosAfterSec] and the user
  /// opted in, automatically ask the crew for help — once. Fully gated: no
  /// opt-in, no crew, or a dismiss already in flight and nothing fires.
  static const _autoSosAfterSec = 180; // 3 min of unanswered ringing

  void _maybeAutoSos() {
    if (_sosSent || _dismissing || _elapsedSec < _autoSosAfterSec) return;
    if (!ref.read(currentSettingsProvider).crewSosEnabled) return;
    final crew = ref.read(crewProvider).value;
    if (crew == null || crew.friends.isEmpty) return;
    _sendSos();
  }

  /// Fan an SOS out to every crew member, once per ring. The notification text
  /// is fixed server-side (NudgeKind.sos) — we only trigger it. Best-effort per
  /// member; the send-nudge function rate-limits duplicates.
  Future<void> _sendSos() async {
    if (_sosSent) return;
    final crew = ref.read(crewProvider).value;
    if (crew == null || crew.friends.isEmpty) return;
    setState(() => _sosSent = true);
    final sent = await pingCrew(ref.read(nudgeServiceProvider),
        crew.friends.map((m) => m.id), NudgeKind.sos);
    if (!mounted) return;
    RiseToast.show(
      context,
      sent > 0
          ? 'Your crew has been alerted — help is on the way 🚨'
          : "Couldn't reach your crew right now.",
      kind: sent > 0 ? RiseToastKind.success : RiseToastKind.error,
    );
  }

  Future<void> _dismiss(String method) async {
    if (_dismissing) return; // guard double-taps / repeated slide fires
    setState(() => _dismissing = true);
    // Silence first, for the same reason stopRinging runs first inside
    // dismissAlarm: someone who has done the work to dismiss must not keep
    // hearing the alarm while a database write finishes.
    unawaited(_ringAudio.stop());
    try {
      await widget.dismissAlarm(widget.alarmId);
    } catch (e) {
      debugPrint('Rise: dismiss failed for ${widget.alarmId}: $e');
      if (mounted) {
        setState(() {
          _dismissing = false;
          _attempt++; // fresh key resets the slide-to-wake so it can fire again
          // The alarm was NOT dismissed, so it must go back to ringing rather
          // than sit silently on a screen the user thinks they've dealt with.
          _audioStarted = false; // the next build restarts the tone
        });
      }
      return;
    }
    // The alarm is now silenced. If the ring screen was torn down during the
    // awaited dismissal (e.g. an OS resume drove a reconcile that disposed it),
    // bail before touching ref — the post-dismiss bookkeeping needs a live
    // element, and the dismissal itself has already succeeded.
    if (!mounted) return;
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
          // Arm the native wake-check NOW, smart or not — the safety net is
          // always on. Smart mode can only *cancel* it later, once sensing is
          // confident the user stayed up; it never defers the arming. This
          // closes the app-killed-mid-window gap: if Rise dies while sensing,
          // the OS-scheduled check still fires exactly as in the default path.
          try {
            await widget.armWakeCheck(alarm, delay);
          } catch (e) {
            debugPrint(
                'Rise: wake-check schedule failed for ${widget.alarmId}: $e');
          }
          if (settings.smartWakeCheck) {
            // Opt-in smart path: sense over the window and, if confident the
            // user got up, cancel the just-armed check. Detached so the ring
            // screen closes immediately (the sensing outlives it); best-effort.
            unawaited(_runSmartStayUp(alarm, delay, _pendingAlertness));
          }
        }
      }
    }
    if (!mounted) return;
    widget.onDismissed?.call();
  }

  /// The opt-in smart stay-up check (arm-then-cancel). The ordinary wake-check
  /// was already armed at dismissal; this senses over the window and — ONLY on
  /// strong evidence the user stayed up — cancels that armed check via the
  /// native [RingScreen.cancelWakeCheck]. Low or unknown confidence (including
  /// any sensing error) simply leaves the check armed, so the safety net can
  /// never be lost: the worst failure mode is an unnecessary "still up?"
  /// prompt, never a missing re-ring. Best-effort and detached from the ring
  /// screen's lifecycle (it may outlive the popped screen); uses only the
  /// injected callbacks (no `ref`/`context`), so it is safe post-dispose.
  Future<void> _runSmartStayUp(
      Alarm alarm, Duration delay, int? alertness) async {
    WakeChallengeDecision decision;
    try {
      decision = await widget.stayUpDecision(alarm, delay, alertness);
    } catch (e) {
      debugPrint('Rise: smart stay-up sense failed for ${alarm.id}: $e');
      decision = WakeChallengeDecision.reCheck; // conservative: stay armed
    }
    if (decision == WakeChallengeDecision.confident) {
      try {
        await widget.cancelWakeCheck(alarm.id);
      } catch (e) {
        // A failed cancel is the safe direction: the armed check just fires.
        debugPrint('Rise: wake-check cancel failed for ${alarm.id}: $e');
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
    unawaited(_ringAudio.stop()); // silence now; see _dismiss
    try {
      await widget.snooze(widget.alarmId, d);
    } catch (e) {
      debugPrint('Rise: snooze failed for ${widget.alarmId}: $e');
      if (mounted) {
        setState(() {
          _dismissing = false;
          _attempt++;
          _audioStarted = false; // snooze failed — keep ringing
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
            Icon(Icons.flag_outlined,
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

  /// A brief, honest note that a phone screen is too dim to truly wake you —
  /// nudging real, bright light. Warm and dismissible (a small ✕), never a gate.
  Widget _lightPrompt() => Container(
        constraints: const BoxConstraints(maxWidth: 340),
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        decoration: BoxDecoration(
          color: RiseColors.accentSoft,
          borderRadius: BorderRadius.circular(RiseRadii.base),
          border: Border.all(color: RiseColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.wb_sunny_outlined,
                size: 16, color: RiseColors.waking),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Screens are too dim to fully wake you. Open a window or turn on '
                'a bright light.',
                style: RiseText.caption.copyWith(color: RiseColors.text),
              ),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              key: const Key('light-prompt-dismiss'),
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _lightPromptDismissed = true),
              child: Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, size: 15, color: RiseColors.textDim),
              ),
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

  Widget _sosButton() => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: TextButton(
          key: const Key('crew-sos-button'),
          onPressed: _dismissing ? null : _sendSos,
          child: Text("Can't wake up? Alert your crew 🚨",
              style: RiseText.body.copyWith(
                  color: RiseColors.textDim, fontWeight: FontWeight.w600)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final alarm = ref
        .watch(alarmsProvider)
        .valueOrNull
        ?.firstWhereOrNull((a) => a.id == widget.alarmId);

    // The tone can only start once the record has loaded, because the record is
    // what names it. Guarded to fire once; scheduling async work is safe here
    // (no setState), and RingAudio.start never throws.
    if (alarm != null && !_audioStarted) {
      _audioStarted = true;
      unawaited(_ringAudio.start(alarm.soundAsset));
    }

    final settings = ref.watch(currentSettingsProvider);
    final crew = ref.watch(crewProvider).value;
    final showSos = settings.crewSosEnabled &&
        !_sosSent &&
        (crew?.friends.isNotEmpty ?? false);
    final events = ref.watch(wakeEventsProvider).value ?? const <WakeEvent>[];
    final snoozeCount = events
            .firstWhereOrNull((e) => e.alarmId == widget.alarmId && e.isOpen)
            ?.snoozeCount ??
        0;
    final canSnooze = snoozeCount < settings.snoozeMaxCount;
    final snoozeMinutes = settings.snoozeDurationMinutes(snoozeCount);
    final label = alarm?.label ?? 'Alarm';
    final queuedLabel = _queuedAlarmId == null
        ? null
        : (ref
                .watch(alarmsProvider)
                .value
                ?.firstWhereOrNull((a) => a.id == _queuedAlarmId)
                ?.label ??
            'Alarm');
    final now = DateTime.now();
    final clock =
        formatClockParts(now.hour, now.minute, use24h: settings.use24HourTime);
    final reduce = MediaQuery.of(context).disableAnimations;

    Widget bell = Container(
      width: 92,
      height: 92,
      decoration: BoxDecoration(
        color: RiseColors.accentSoft,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Icon(Icons.notifications_active,
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

    final content = SafeArea(
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
                Text('${clock.hour}:${clock.minute}',
                    style: RiseText.mono(size: 72, weight: FontWeight.w500)),
                if (clock.period.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Text(clock.period,
                      style: RiseText.mono(size: 20, color: RiseColors.textDim)),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Text(label,
                style: RiseText.title.copyWith(color: RiseColors.textDim)),
            if (_queuedAlarmId != null) ...[
              const SizedBox(height: 8),
              Text('Next: $queuedLabel queued',
                  style: RiseText.body.copyWith(color: RiseColors.textDim)),
            ],
            if (settings.wakeIntention.isNotEmpty) ...[
              const SizedBox(height: 18),
              _planReminder(settings.wakeIntention),
            ],
            if (settings.realLightPrompt && !_lightPromptDismissed) ...[
              const SizedBox(height: 12),
              _lightPrompt(),
            ],
            const Spacer(),
            if (isMissioned && missionCount > 1) ...[
              Text('${_completions + 1} of $missionCount',
                  style: RiseText.mono(size: 14, color: RiseColors.textDim)),
              const SizedBox(height: 12),
            ],
            gate,
            if (canSnooze) _snoozeButton(snoozeMinutes),
            if (showSos) _sosButton(),
          ],
        ),
      ),
    );

    // When the opt-in sunrise is on, paint the animated dawn gradient behind the
    // (unchanged) content. Off → the plain background, byte-for-byte as before.
    return Scaffold(
      backgroundColor: RiseColors.appBg,
      body: _sunriseActive
          ? Stack(
              children: [
                Positioned.fill(
                  key: const Key('sunrise-bg'),
                  child: AnimatedBuilder(
                    animation: _sunrise,
                    builder: (_, __) => DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: sunriseGradient(_sunrise.value),
                      ),
                    ),
                  ),
                ),
                content,
              ],
            )
          : content,
    );
  }
}
