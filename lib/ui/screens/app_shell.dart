import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/permission_gateway.dart';
import '../../domain/alarm.dart';
import '../components/toast.dart';
import '../missions/mission_host.dart';
import '../state/alarm_providers.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'create_edit_screen.dart';
import 'home_screen.dart';
import 'profile_screen.dart';
import 'ring_screen.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, this.permissions = const NativePermissionGateway()});

  final PermissionGateway permissions;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _tab = 0;

  void _openNew() => ref.read(draftProvider.notifier).startNew();
  void _openEdit(Alarm a) => ref.read(draftProvider.notifier).startEdit(a);

  void _preview() {
    final next = ref.read(nextOccurrenceProvider).value;
    final alarms = ref.read(alarmsProvider).value ?? const <Alarm>[];
    final id = next?.alarmId ?? (alarms.isEmpty ? 0 : alarms.first.id);
    final navigator = Navigator.of(context);
    navigator.push(MaterialPageRoute<void>(
      builder: (_) => RingScreen(
        alarmId: id,
        dismissAlarm: (_) async {}, // preview only — nothing is actually ringing
        missionBuilder: buildMission,
        onDismissed: navigator.maybePop,
      ),
    ));
  }

  Widget _activeTab() {
    switch (_tab) {
      case 1:
        return const _ComingSoon(
            icon: Icons.groups_outlined,
            title: 'Crew',
            body: 'Wake up with friends and keep each other honest. Coming soon.');
      case 2:
        return const _ComingSoon(
            icon: Icons.bedtime_outlined,
            title: 'Sleep',
            body: 'Sleep insights and smart wake windows. Coming soon.');
      case 3:
        return ProfileScreen(permissions: widget.permissions);
      default:
        return HomeScreen(
            onNew: _openNew, onEdit: _openEdit, onPreview: _preview);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = ref.watch(draftProvider) != null;
    final toast = ref.watch(toastProvider);

    return PopScope(
      canPop: !editing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && editing) ref.read(draftProvider.notifier).clear();
      },
      child: Scaffold(
        backgroundColor: RiseColors.appBg,
        body: ToastHost(
          message: toast,
          onHide: () => ref.read(toastProvider.notifier).state = null,
          child: Stack(
            children: [
              _activeTab(),
              if (editing)
                Positioned.fill(
                  child: Material(
                    color: RiseColors.appBg,
                    child: CreateEditScreen(onDone: () {}),
                  ),
                ),
            ],
          ),
        ),
        bottomNavigationBar: editing ? null : _tabBar(),
      ),
    );
  }

  Widget _tabBar() {
    const items = [
      (icon: Icons.alarm, label: 'Alarms'),
      (icon: Icons.groups_outlined, label: 'Crew'),
      (icon: Icons.bedtime_outlined, label: 'Sleep'),
      (icon: Icons.person_outline, label: 'Profile'),
    ];
    return Container(
      decoration: const BoxDecoration(
        color: RiseColors.card,
        border: Border(top: BorderSide(color: RiseColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _tab = i),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(items[i].icon,
                            size: 22,
                            color: i == _tab
                                ? RiseColors.primary
                                : RiseColors.textFaint),
                        const SizedBox(height: 3),
                        Text(items[i].label,
                            style: RiseText.caption.copyWith(
                                fontSize: 11,
                                color: i == _tab
                                    ? RiseColors.primary
                                    : RiseColors.textFaint,
                                fontWeight: i == _tab
                                    ? FontWeight.w600
                                    : FontWeight.w500)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComingSoon extends StatelessWidget {
  const _ComingSoon(
      {required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 44, color: RiseColors.textFaint),
            const SizedBox(height: 16),
            Text(title, style: RiseText.title),
            const SizedBox(height: 8),
            Text(body,
                textAlign: TextAlign.center,
                style: RiseText.body.copyWith(color: RiseColors.textDim)),
          ],
        ),
      ),
    );
  }
}
