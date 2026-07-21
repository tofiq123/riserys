import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/permission_gateway.dart';
import '../../domain/alarm.dart';
import '../backup_sync_host.dart';
import '../components/toast.dart';
import '../feed_publisher.dart';
import '../missions/mission_host.dart';
import '../push_registrar_host.dart';
import '../state/alarm_providers.dart';
import '../state/auth_providers.dart';
import '../status_publisher.dart';
import '../stats_sync_publisher.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'create_edit_screen.dart';
import 'crew_screen.dart';
import 'home_screen.dart';
import 'profile_screen.dart';
import 'ring_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';
import 'username_claim_screen.dart';

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

  Widget _activeTab(BuildContext context) {
    switch (_tab) {
      case 1:
        return const CrewScreen();
      case 2:
        return const StatsScreen();
      case 3:
        return ProfileScreen(
          permissions: widget.permissions,
          onSettings: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
        );
      default:
        return HomeScreen(
          onNew: _openNew,
          onEdit: _openEdit,
          onPreview: _preview,
          onStreak: () => setState(() => _tab = 2),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = ref.watch(draftProvider) != null;
    final account = ref.watch(accountProvider).value;
    final needsClaim = account != null && account.needsUsername;
    final toast = ref.watch(toastProvider);

    return PushRegistrarHost(
      child: BackupSyncHost(
        child: StatusPublisherHost(
          child: StatsSyncHost(
            child: FeedPublisherHost(
            child: PopScope(
            canPop: !editing && !needsClaim,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop && editing) ref.read(draftProvider.notifier).clear();
            },
            child: Scaffold(
              backgroundColor: RiseColors.appBg,
              body: ToastHost(
                message: toast?.message,
                kind: toast?.kind ?? RiseToastKind.info,
                onHide: () => ref.read(toastProvider.notifier).state = null,
                child: Stack(
                  children: [
                    _activeTab(context),
                    if (editing)
                      Positioned.fill(
                        child: Material(
                          color: RiseColors.appBg,
                          child: CreateEditScreen(onDone: () {}),
                        ),
                      ),
                    if (needsClaim)
                      Positioned.fill(
                        child: Material(
                          color: RiseColors.appBg,
                          child: UsernameClaimScreen(
                            initialDisplayName: account.displayName,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              bottomNavigationBar: (editing || needsClaim) ? null : _tabBar(),
            ),
          ),
        ),
        ),
      ),
    ),
    );
  }

  Widget _tabBar() {
    const items = [
      (icon: Icons.alarm, label: 'Alarms'),
      (icon: Icons.groups_outlined, label: 'Crew'),
      (icon: Icons.insights_outlined, label: 'Stats'),
      (icon: Icons.person_outline, label: 'Profile'),
    ];
    return Container(
      decoration: BoxDecoration(
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
