import 'package:flutter/material.dart';

import '../../data/native/alarm_api.g.dart';
import '../../data/permission_gateway.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'rise_buttons.dart';
import 'rise_card.dart';
import 'rise_spinner.dart';

/// The four alarm-reliability permissions with live status and a Grant action.
/// Loads on mount and refreshes on app-resume (e.g. after the user returns from
/// a system settings screen). Shared by onboarding and Profile.
class PermissionsSection extends StatefulWidget {
  const PermissionsSection({super.key, required this.gateway});

  final PermissionGateway gateway;

  @override
  State<PermissionsSection> createState() => _PermissionsSectionState();
}

class _PermissionsSectionState extends State<PermissionsSection>
    with WidgetsBindingObserver {
  AlarmPermissions? _perms;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final p = await widget.gateway.status();
    if (mounted) setState(() => _perms = p);
  }

  Future<void> _grant(Future<void> Function() action) async {
    await action();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final p = _perms;
    if (p == null) {
      return const Center(
          child: Padding(
              padding: EdgeInsets.all(20), child: RiseSpinner(size: 16)));
    }
    return Column(
      children: [
        _row('Notifications',
            'So your alarm can actually ring and show up — even on silent.',
            p.notifications,
            () => _grant(widget.gateway.requestNotifications)),
        _row('Exact alarm',
            'So it goes off right on time, not a few minutes late.',
            p.exactAlarm, () => _grant(widget.gateway.openExactAlarm)),
        _row('Full-screen alarm',
            'So it fills the screen and wakes you, even when the phone is locked.',
            p.fullScreenIntent,
            () => _grant(widget.gateway.openFullScreenIntent)),
        _row('Unrestricted battery',
            'So the system never quietly puts your alarm to sleep overnight.',
            p.batteryUnrestricted, () => _grant(widget.gateway.openBattery)),
        const SizedBox(height: 4),
        Center(child: GhostButton(label: 'Re-check', onPressed: _refresh)),
      ],
    );
  }

  Widget _row(String label, String why, bool granted, VoidCallback onGrant) {
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
}
