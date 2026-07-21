import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/auth/auth_service.dart';
import '../../data/permission_gateway.dart';
import '../../domain/alarm.dart';
import '../components/permissions_section.dart';
import '../components/rise_buttons.dart';
import '../components/rise_card.dart';
import '../components/sound_chips.dart';
import '../components/time_dial.dart';
import '../state/alarm_providers.dart';
import '../state/auth_providers.dart';
import '../state/settings_providers.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'setup_guardian_screen.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.onDone,
    this.permissions = const NativePermissionGateway(),
  });

  final VoidCallback onDone;
  final PermissionGateway permissions;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  final _intention = TextEditingController();
  int _page = 0;

  /// Sign-in step (final page, configured-auth only) UI state.
  bool _signingIn = false;
  String? _signInError;

  /// The optional steady wake time (24-hour), or null until the user opts in.
  int? _goalHour;
  int? _goalMinute;

  /// First-alarm wizard state. Nothing is created unless [_wantFirstAlarm] is
  /// opted into, so skipping onboarding never conjures an alarm.
  bool _wantFirstAlarm = false;
  int _alarmHour = 7;
  int _alarmMinute = 0;
  String _alarmMission = 'none';

  /// Whether the built-in sign-in step is appended as the final page. Only when
  /// auth is configured; with the default [DisabledAuthService] the flow is
  /// unchanged (six pages), so existing onboarding tests stay valid.
  bool get _signInStep => ref.read(authServiceProvider) is! DisabledAuthService;

  /// The last page index — the optional sign-in step appends one page.
  int get _lastPage => _signInStep ? 6 : 5;

  /// A friendly subset of dismiss missions for the first alarm. The full set
  /// lives in Create/Edit; here we keep the choice small and welcoming.
  static const _wizardMissions = <String, String>{
    'none': 'None',
    'math': 'Math',
    'tap': 'Tap',
    'memory': 'Memory',
  };

  /// Tappable starters for the implementation-intention prompt.
  static const _suggestions = [
    'Put my feet on the floor',
    'Walk to the kitchen',
    'Stand up and stretch',
  ];

  @override
  void dispose() {
    _controller.dispose();
    _intention.dispose();
    super.dispose();
  }

  void _next() {
    if (_page < _lastPage) {
      _controller.nextPage(
          duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
    } else {
      _finish();
    }
  }

  /// Persists the (optional) intention and steady wake time, then hands off to
  /// [OnboardingScreen.onDone]. Each persist is best-effort: a settings failure
  /// must never trap the user in onboarding.
  void _finish() {
    final text = _intention.text.trim();
    if (text.isNotEmpty) {
      try {
        ref.read(settingsProvider.notifier).setWakeIntention(text);
      } catch (_) {}
    }
    if (_goalHour != null && _goalMinute != null) {
      try {
        ref
            .read(settingsProvider.notifier)
            .setTargetWakeTime(_goalHour!, _goalMinute!);
      } catch (_) {}
    }
    // Create the first alarm only if the user opted in — this is the one branch
    // that touches the alarm engine, so skippers never read it. Fire-and-forget
    // with error handling: a save/arm hiccup must never trap the user in
    // onboarding. AlarmMutations captures its repo + sync eagerly, so it's safe
    // to run after onDone tears this screen down.
    if (_wantFirstAlarm) {
      try {
        final alarm = Alarm(
          id: 0,
          hour: _alarmHour,
          minute: _alarmMinute,
          days: const {1, 2, 3, 4, 5},
          mission: _alarmMission,
        );
        ref.read(alarmMutationsProvider).save(alarm).catchError((_) {});
      } catch (_) {}
    }
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RiseColors.appBg,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 8, top: 4),
                child: _page < _lastPage
                    ? GhostButton(label: 'Skip', onPressed: _finish)
                    : const SizedBox(height: 44),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _intro(
                    icon: Icons.notifications_active,
                    title: 'Wake up, for real',
                    body:
                        'Rise rings through silent mode, Focus, and a locked screen — and makes sure you actually get up.',
                  ),
                  _intro(
                    icon: Icons.psychology_alt,
                    title: 'Wake up all the way',
                    body:
                        'Turn your alarm off with a quick mission — a little math, a pattern, or a button hold. A gentle nudge past the half-asleep swipe.',
                  ),
                  _intentionPage(),
                  _sleepGoalPage(),
                  _firstAlarmPage(),
                  _permissionsPage(),
                  if (_signInStep) _signInPage(),
                ],
              ),
            ),
            _dots(),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  RiseSpacing.screen, 12, RiseSpacing.screen, 16),
              // The sign-in page owns its own actions, so the persistent button
              // steps aside there (kept as spacing to avoid a layout jump).
              child: _signInStep && _page == _lastPage
                  ? const SizedBox(height: 44)
                  : PrimaryButton(
                      label: _page < _lastPage ? 'Next' : 'Start using Rise',
                      onPressed: _next,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _intro(
      {required IconData icon, required String title, required String body}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: RiseColors.accentSoft,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Icon(icon, size: 44, color: RiseColors.accent),
          ),
          const SizedBox(height: 28),
          Text(title, textAlign: TextAlign.center, style: RiseText.display),
          const SizedBox(height: 12),
          Text(body,
              textAlign: TextAlign.center,
              style: RiseText.body.copyWith(color: RiseColors.textDim)),
        ],
      ),
    );
  }

  /// The implementation-intention step. A concrete "when X, I will Y" plan is
  /// one of the most evidence-backed nudges for follow-through, and it costs the
  /// user nothing — so it stays fully optional and skippable.
  Widget _intentionPage() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          RiseSpacing.screen, 12, RiseSpacing.screen, 12),
      children: [
        Text('Make a tiny plan', style: RiseText.title),
        const SizedBox(height: 8),
        Text(
            'Deciding your first move in advance makes getting up easier. When '
            'your alarm rings, what will you do first?',
            style: RiseText.body.copyWith(color: RiseColors.textDim)),
        const SizedBox(height: 20),
        Text('When my alarm rings, I will…',
            style: RiseText.body.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final s in _suggestions) _chip(s)],
        ),
        const SizedBox(height: 14),
        TextField(
          key: const Key('intention-field'),
          controller: _intention,
          textCapitalization: TextCapitalization.sentences,
          cursorColor: RiseColors.primary,
          onChanged: (_) => setState(() {}), // refresh chip highlight
          decoration: const InputDecoration(
            hintText: 'Put my feet on the floor',
          ),
        ),
        const SizedBox(height: 10),
        Text('Optional — you can skip this and set it later in Settings.',
            style: RiseText.caption),
      ],
    );
  }

  Widget _chip(String label) {
    final selected = _intention.text.trim() == label;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() {
        _intention.text = label;
        _intention.selection =
            TextSelection.collapsed(offset: label.length);
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? RiseColors.accentSoft : RiseColors.surface2,
          borderRadius: BorderRadius.circular(RiseRadii.pill),
          border: Border.all(
              color: selected ? RiseColors.accent : RiseColors.border),
        ),
        child: Text(label,
            style: RiseText.caption.copyWith(
                color: selected ? RiseColors.text : RiseColors.textDim,
                fontWeight: FontWeight.w600)),
      ),
    );
  }

  /// The steady-wake-time step. A consistent wake time is a gentle rhythm
  /// anchor — framed as general wellness, never a treatment. Fully optional and
  /// skippable; the user opts in explicitly before any time is captured.
  Widget _sleepGoalPage() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          RiseSpacing.screen, 12, RiseSpacing.screen, 12),
      children: [
        Text('Aim for a steady wake time', style: RiseText.title),
        const SizedBox(height: 8),
        Text(
            'Waking around the same time most days helps your body settle into '
            'a rhythm. Set a gentle anchor if you\'d like — it\'s just for you.',
            style: RiseText.body.copyWith(color: RiseColors.textDim)),
        const SizedBox(height: 20),
        if (_goalHour == null)
          GestureDetector(
            key: const Key('sleep-goal-add'),
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() {
              _goalHour = 7;
              _goalMinute = 0;
            }),
            child: RiseCard(
              child: Row(
                children: [
                  Icon(Icons.wb_sunny_outlined,
                      color: RiseColors.waking, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Set a steady wake time',
                        style: RiseText.body
                            .copyWith(fontWeight: FontWeight.w600)),
                  ),
                  Icon(Icons.add, color: RiseColors.textFaint, size: 20),
                ],
              ),
            ),
          )
        else ...[
          RiseCard(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: TimeDial(
              use24h: ref.watch(currentSettingsProvider).use24HourTime,
              value: (
                hour12: _goalHour! % 12 == 0 ? 12 : _goalHour! % 12,
                minute: _goalMinute!,
                isAm: _goalHour! < 12,
              ),
              onChanged: (t) => setState(() {
                _goalHour = Alarm.to24Hour(t.hour12, t.isAm);
                _goalMinute = t.minute;
              }),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: GhostButton(
              label: 'Remove',
              onPressed: () => setState(() {
                _goalHour = null;
                _goalMinute = null;
              }),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Text('Optional — you can set or change this later in Settings.',
            style: RiseText.caption),
      ],
    );
  }

  /// The first-alarm wizard: a skippable step so first run isn't a blank Alarms
  /// tab. The user opts in explicitly, then picks a time and (optionally) a
  /// wake mission. The alarm is created on finish (see [_finish]).
  Widget _firstAlarmPage() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          RiseSpacing.screen, 12, RiseSpacing.screen, 12),
      children: [
        Text('Set your first alarm', style: RiseText.title),
        const SizedBox(height: 8),
        Text(
            'Get one alarm ready now so you\'re set for tomorrow. It repeats on '
            'weekdays — you can change everything later.',
            style: RiseText.body.copyWith(color: RiseColors.textDim)),
        const SizedBox(height: 20),
        if (!_wantFirstAlarm)
          GestureDetector(
            key: const Key('first-alarm-add'),
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _wantFirstAlarm = true),
            child: RiseCard(
              child: Row(
                children: [
                  Icon(Icons.alarm_add,
                      color: RiseColors.accent, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Add my first alarm',
                        style: RiseText.body
                            .copyWith(fontWeight: FontWeight.w600)),
                  ),
                  Icon(Icons.add, color: RiseColors.textFaint, size: 20),
                ],
              ),
            ),
          )
        else ...[
          RiseCard(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: TimeDial(
              use24h: ref.watch(currentSettingsProvider).use24HourTime,
              value: (
                hour12: _alarmHour % 12 == 0 ? 12 : _alarmHour % 12,
                minute: _alarmMinute,
                isAm: _alarmHour < 12,
              ),
              onChanged: (t) => setState(() {
                _alarmHour = Alarm.to24Hour(t.hour12, t.isAm);
                _alarmMinute = t.minute;
              }),
            ),
          ),
          const SizedBox(height: 16),
          Text('Wake mission',
              style: RiseText.body.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('A quick task to make sure you\'re actually up. Optional.',
              style: RiseText.caption),
          const SizedBox(height: 12),
          SoundChips(
            sounds: _wizardMissions.values.toList(),
            selected: _wizardMissions[_alarmMission] ?? _wizardMissions['none']!,
            onChanged: (label) => setState(() {
              _alarmMission = _wizardMissions.entries
                  .firstWhere((e) => e.value == label)
                  .key;
            }),
          ),
          const SizedBox(height: 12),
          Center(
            child: GhostButton(
              label: 'Not now',
              onPressed: () => setState(() {
                _wantFirstAlarm = false;
                _alarmMission = 'none';
              }),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Text('Optional — you can add or change alarms anytime.',
            style: RiseText.caption),
      ],
    );
  }

  Widget _permissionsPage() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          RiseSpacing.screen, 12, RiseSpacing.screen, 12),
      children: [
        Text('Ring through anything', style: RiseText.title),
        const SizedBox(height: 8),
        Text(
            'Just a few permissions so your alarm always reaches you — through '
            'silent mode, a locked screen, or when the phone tries to doze off.',
            style: RiseText.body.copyWith(color: RiseColors.textDim)),
        const SizedBox(height: 18),
        PermissionsSection(gateway: widget.permissions),
        const SizedBox(height: 4),
        Center(
          child: GhostButton(
            label: 'Open Setup Guardian',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) =>
                    SetupGuardianScreen(permissions: widget.permissions))),
          ),
        ),
      ],
    );
  }

  /// The final, sign-in step — appended only when auth is configured (see
  /// [_signInStep]). A standard close to onboarding: one clear primary action
  /// (Google) and a quiet way to keep going solo. Either path finishes; a
  /// failed sign-in never traps the user, since "Continue as guest" always
  /// completes onboarding.
  Widget _signInPage() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: RiseColors.accentSoft,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Icon(Icons.cloud_sync,
                size: 44, color: RiseColors.accent),
          ),
          const SizedBox(height: 28),
          Text('Save your progress',
              textAlign: TextAlign.center, style: RiseText.display),
          const SizedBox(height: 12),
          Text(
              'Sign in to save your streak and wake up with your crew — or keep '
              'going solo.',
              textAlign: TextAlign.center,
              style: RiseText.body.copyWith(color: RiseColors.textDim)),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PrimaryButton(
                  label: 'Sign in with Google',
                  icon: Icons.login,
                  onPressed: _signingIn ? null : _signInAndFinish,
                ),
                if (_signingIn)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: RiseColors.primaryText),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          GhostButton(
            label: 'Continue as guest',
            onPressed: _signingIn ? null : _finish,
          ),
          if (_signInError != null) ...[
            const SizedBox(height: 10),
            Text(_signInError!,
                textAlign: TextAlign.center,
                style: RiseText.caption.copyWith(color: RiseColors.danger)),
          ],
        ],
      ),
    );
  }

  /// Signs in with Google, then finishes onboarding. A cancel/error keeps the
  /// user on this page with a gentle note — "Continue as guest" still works, so
  /// finishing is never blocked.
  Future<void> _signInAndFinish() async {
    if (_signingIn) return;
    setState(() {
      _signingIn = true;
      _signInError = null;
    });
    try {
      await ref.read(authServiceProvider).signInWithGoogle();
      _finish();
    } catch (_) {
      if (mounted) {
        setState(() => _signInError =
            'Sign-in didn\'t complete. Try again, or continue as guest.');
      }
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  Widget _dots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i <= _lastPage; i++)
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: i == _page ? RiseColors.primary : RiseColors.border,
              shape: BoxShape.circle,
            ),
          ),
      ],
    );
  }
}
