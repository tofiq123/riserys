import 'package:flutter/material.dart';

import '../../data/native/alarm_api.g.dart';
import '../components/rise_buttons.dart';
import '../components/rise_card.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Abstracts the native permission calls so onboarding is testable without the
/// platform channel. Production uses [NativePermissionGateway].
abstract interface class PermissionGateway {
  Future<AlarmPermissions> status();
  Future<void> requestNotifications();
  Future<void> openExactAlarm();
  Future<void> openFullScreenIntent();
  Future<void> openBattery();
}

class NativePermissionGateway implements PermissionGateway {
  const NativePermissionGateway();
  @override
  Future<AlarmPermissions> status() => AlarmHostApi().getPermissions();
  @override
  Future<void> requestNotifications() =>
      AlarmHostApi().requestNotificationPermission();
  @override
  Future<void> openExactAlarm() => AlarmHostApi().openExactAlarmSettings();
  @override
  Future<void> openFullScreenIntent() =>
      AlarmHostApi().openFullScreenIntentSettings();
  @override
  Future<void> openBattery() => AlarmHostApi().openBatterySettings();
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.onDone,
    this.permissions = const NativePermissionGateway(),
  });

  final VoidCallback onDone;
  final PermissionGateway permissions;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with WidgetsBindingObserver {
  final _controller = PageController();
  int _page = 0;
  AlarmPermissions? _perms;

  static const _lastPage = 2;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning from a system settings screen (exact-alarm, battery, …) should
    // refresh the granted/needed checks.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final p = await widget.permissions.status();
    if (mounted) setState(() => _perms = p);
  }

  Future<void> _grant(Future<void> Function() action) async {
    await action();
    await _refresh();
  }

  void _next() {
    if (_page < _lastPage) {
      _controller.nextPage(
          duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
    } else {
      widget.onDone();
    }
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
                    ? GhostButton(label: 'Skip', onPressed: widget.onDone)
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
                    title: 'Prove you\'re awake',
                    body:
                        'Turn an alarm off only by finishing a quick mission — solve some math, repeat a pattern, or hold a button. No half-asleep swipe.',
                  ),
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

  Widget _permissionsPage() {
    final p = _perms;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          RiseSpacing.screen, 12, RiseSpacing.screen, 12),
      children: [
        Text('Ring through anything', style: RiseText.title),
        const SizedBox(height: 8),
        Text(
            'Rise needs a few permissions to reach you on silent, locked, or dozing.',
            style: RiseText.body.copyWith(color: RiseColors.textDim)),
        const SizedBox(height: 18),
        if (p == null)
          const Center(
              child: Padding(
                  padding: EdgeInsets.all(20), child: Text('Checking…')))
        else ...[
          _permRow('Notifications', 'Show the alarm and let it ring.',
              p.notifications, () => _grant(widget.permissions.requestNotifications)),
          _permRow('Exact alarm', 'Fire at the exact minute.', p.exactAlarm,
              () => _grant(widget.permissions.openExactAlarm)),
          _permRow('Full-screen alarm', 'Show over the lock screen.',
              p.fullScreenIntent,
              () => _grant(widget.permissions.openFullScreenIntent)),
          _permRow('Unrestricted battery',
              'Don\'t let the system doze the alarm.', p.batteryUnrestricted,
              () => _grant(widget.permissions.openBattery)),
          const SizedBox(height: 4),
          Center(child: GhostButton(label: 'Re-check', onPressed: _refresh)),
        ],
      ],
    );
  }

  Widget _permRow(String label, String why, bool granted, VoidCallback onGrant) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: RiseCard(
        child: Row(
          children: [
            Icon(granted ? Icons.check_circle : Icons.circle_outlined,
                color: granted ? RiseColors.positive : RiseColors.textFaint,
                size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style:
                          RiseText.body.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(why, style: RiseText.caption),
                ],
              ),
            ),
            if (!granted) SecondaryButton(label: 'Grant', onPressed: onGrant),
          ],
        ),
      ),
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
