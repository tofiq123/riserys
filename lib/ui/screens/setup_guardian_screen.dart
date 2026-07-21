import 'package:flutter/material.dart';

import '../../data/device_info_gateway.dart';
import '../../data/native/alarm_api.g.dart';
import '../../data/permission_gateway.dart';
import '../../domain/oem_guidance.dart';
import '../../domain/reliability_check.dart';
import '../components/rise_buttons.dart';
import '../components/rise_card.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// The Setup Guardian: a reliability dashboard listing the checks that decide
/// whether the alarm actually fires. Each check is a plain status (ok /
/// needsAttention / unknown) with why-it-matters and a "Fix" that opens the
/// right system screen. Re-checks on mount and on app-resume, because OEMs and
/// OS updates silently revert these.
///
/// Pure status logic lives in [buildReliabilityChecks] / [ReliabilitySummary]
/// and the OEM copy in [oemGuidanceFor]; this screen is the thin platform layer.
class SetupGuardianScreen extends StatefulWidget {
  const SetupGuardianScreen({
    super.key,
    this.permissions = const NativePermissionGateway(),
    this.deviceInfo,
    this.showBack = true,
  });

  final PermissionGateway permissions;

  /// Injectable for tests; defaults to the native reader in production.
  final DeviceInfoGateway? deviceInfo;

  /// Hidden when the screen is embedded (e.g. onboarding) rather than pushed.
  final bool showBack;

  @override
  State<SetupGuardianScreen> createState() => _SetupGuardianScreenState();
}

class _SetupGuardianScreenState extends State<SetupGuardianScreen>
    with WidgetsBindingObserver {
  late final DeviceInfoGateway _deviceInfo =
      widget.deviceInfo ?? NativeDeviceInfoGateway();

  AlarmPermissions? _perms;
  String? _manufacturer;
  bool _android = true;
  bool _oemExpanded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning from a system settings screen should re-run the checks.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _load() async {
    _android = _deviceInfo.isAndroid;
    _manufacturer = await _deviceInfo.androidManufacturer();
    await _refresh();
  }

  Future<void> _refresh() async {
    final p = await widget.permissions.status();
    if (mounted) setState(() => _perms = p);
  }

  Future<void> _fix(Future<void> Function() action) async {
    await action();
    await _refresh();
  }

  /// The gateway action for a check, or null for the OEM-autostart row (which
  /// expands to guidance rather than opening a single settings screen).
  Future<void> Function()? _actionFor(ReliabilityCheckId id) {
    switch (id) {
      case ReliabilityCheckId.notifications:
        return widget.permissions.requestNotifications;
      case ReliabilityCheckId.exactAlarm:
        return widget.permissions.openExactAlarm;
      case ReliabilityCheckId.fullScreenIntent:
        return widget.permissions.openFullScreenIntent;
      case ReliabilityCheckId.battery:
        return widget.permissions.openBattery;
      case ReliabilityCheckId.oemAutostart:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _perms;
    return Scaffold(
      backgroundColor: RiseColors.appBg,
      body: SafeArea(
        child: p == null
            ? Center(child: Text('Checking…', style: RiseText.body))
            : _dashboard(p),
      ),
    );
  }

  Widget _dashboard(AlarmPermissions p) {
    final checks = buildReliabilityChecks(
      isAndroid: _android,
      notifications: p.notifications,
      exactAlarm: p.exactAlarm,
      fullScreenIntent: p.fullScreenIntent,
      batteryUnrestricted: p.batteryUnrestricted,
    );
    final summary = ReliabilitySummary(checks);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          RiseSpacing.screen, 8, RiseSpacing.screen, 40),
      children: [
        if (widget.showBack)
          Row(
            children: [
              GestureDetector(
                key: const Key('guardian-back'),
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).maybePop(),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child:
                      Icon(Icons.arrow_back, color: RiseColors.text, size: 22),
                ),
              ),
              const SizedBox(width: 8),
              Text('Setup Guardian', style: RiseText.title),
            ],
          )
        else
          Text('Setup Guardian', style: RiseText.title),
        const SizedBox(height: 6),
        Text(
            'These checks decide whether your alarm actually fires. Rise '
            're-checks them every time you open the app.',
            style: RiseText.caption),
        const SizedBox(height: 16),
        _summaryCard(summary),
        const SizedBox(height: 16),
        for (final check in checks) _checkCard(check),
        const SizedBox(height: 4),
        Center(
          child: GhostButton(
            label: 'Re-check',
            onPressed: _refresh,
          ),
        ),
      ],
    );
  }

  Widget _summaryCard(ReliabilitySummary s) {
    final color = _statusColor(s.overall);
    return RiseCard(
      key: const Key('guardian-summary'),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Text('${s.score}',
                style: RiseText.mono(
                    size: 18,
                    weight: FontWeight.w700,
                    color: RiseColors.primaryText)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.headline,
                    style: RiseText.body.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('${s.okCount} of ${s.okCount + s.attentionCount} ready',
                    style: RiseText.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _checkCard(ReliabilityCheck check) {
    final isOem = check.id == ReliabilityCheckId.oemAutostart;
    final action = _actionFor(check.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: RiseCard(
        key: Key('guardian-check-${check.id.name}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_statusIcon(check.status),
                    color: _statusColor(check.status), size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(check.title,
                          style: RiseText.body
                              .copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(check.why, style: RiseText.caption),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _trailing(check, isOem, action),
              ],
            ),
            if (isOem && _oemExpanded) _oemSteps(),
          ],
        ),
      ),
    );
  }

  Widget _trailing(
      ReliabilityCheck check, bool isOem, Future<void> Function()? action) {
    if (isOem) {
      return SecondaryButton(
        label: _oemExpanded ? 'Hide' : 'How to fix',
        onPressed: () => setState(() => _oemExpanded = !_oemExpanded),
      );
    }
    if (check.isOk || action == null) return const SizedBox.shrink();
    return SecondaryButton(label: 'Fix', onPressed: () => _fix(action));
  }

  Widget _oemSteps() {
    final guidance = oemGuidanceFor(_manufacturer);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 1, color: RiseColors.divider),
          const SizedBox(height: 12),
          Text(guidance.vendorLabel.toUpperCase(),
              style: RiseText.sectionLabel),
          const SizedBox(height: 6),
          Text(guidance.summary, style: RiseText.caption),
          const SizedBox(height: 12),
          for (var i = 0; i < guidance.steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${i + 1}.',
                      style: RiseText.mono(
                          size: 13, color: RiseColors.textDim)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(guidance.steps[i], style: RiseText.body)),
                ],
              ),
            ),
          const SizedBox(height: 4),
          SecondaryButton(
            label: 'Open battery settings',
            icon: Icons.battery_saver,
            onPressed: () => _fix(widget.permissions.openBattery),
          ),
        ],
      ),
    );
  }

  static IconData _statusIcon(ReliabilityStatus s) {
    switch (s) {
      case ReliabilityStatus.ok:
        return Icons.check_circle;
      case ReliabilityStatus.needsAttention:
        return Icons.error_outline;
      case ReliabilityStatus.unknown:
        return Icons.help_outline;
    }
  }

  static Color _statusColor(ReliabilityStatus s) {
    switch (s) {
      case ReliabilityStatus.ok:
        return RiseColors.positive;
      case ReliabilityStatus.needsAttention:
        return RiseColors.danger;
      case ReliabilityStatus.unknown:
        return RiseColors.waking;
    }
  }
}
