import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/permission_gateway.dart';
import '../../domain/alarm.dart';
import '../components/permissions_section.dart';
import '../components/rise_buttons.dart';
import '../components/rise_card.dart';
import '../components/time_dial.dart';
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

  /// The optional steady wake time (24-hour), or null until the user opts in.
  int? _goalHour;
  int? _goalMinute;

  static const _lastPage = 4;

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
                  _permissionsPage(),
                ],
              ),
            ),
            _dots(),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  RiseSpacing.screen, 12, RiseSpacing.screen, 16),
              child: PrimaryButton(
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
                  const Icon(Icons.wb_sunny_outlined,
                      color: RiseColors.waking, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Set a steady wake time',
                        style: RiseText.body
                            .copyWith(fontWeight: FontWeight.w600)),
                  ),
                  const Icon(Icons.add, color: RiseColors.textFaint, size: 20),
                ],
              ),
            ),
          )
        else ...[
          RiseCard(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: TimeDial(
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
