import 'package:flutter/material.dart';

import '../data/alarm_sync_service.dart';
import '../data/local/alarm_repository.dart';
import '../data/native/alarm_api.g.dart';
import '../domain/alarm.dart';

/// Throwaway UI that proves the alarm engine works. Plan 3 replaces this
/// entirely with the designed Home screen.
class DevHomePage extends StatefulWidget {
  const DevHomePage({super.key, required this.repository});

  final AlarmRepository repository;

  @override
  State<DevHomePage> createState() => _DevHomePageState();
}

class _DevHomePageState extends State<DevHomePage> {
  AlarmPermissions? _permissions;

  @override
  void initState() {
    super.initState();
    _refreshPermissions();
  }

  Future<void> _refreshPermissions() async {
    final p = await AlarmHostApi().getPermissions();
    if (mounted) setState(() => _permissions = p);
  }

  Future<void> _addAlarmIn(Duration delay) async {
    final when = DateTime.now().add(delay);
    await widget.repository.upsert(
      Alarm(id: 0, hour: when.hour, minute: when.minute, label: 'Test alarm'),
    );
    await AlarmSyncService.instance.reconcileNow();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = _permissions;
    return Scaffold(
      appBar: AppBar(title: const Text('Rise — engine test')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Permissions', style: TextStyle(fontWeight: FontWeight.bold)),
          if (p == null)
            const Text('checking…')
          else ...[
            _PermissionRow('Notifications', p.notifications,
                () => AlarmHostApi().requestNotificationPermission()),
            _PermissionRow('Exact alarm', p.exactAlarm,
                () => AlarmHostApi().openExactAlarmSettings()),
            _PermissionRow('Full-screen intent', p.fullScreenIntent,
                () => AlarmHostApi().openFullScreenIntentSettings()),
            _PermissionRow('Battery unrestricted', p.batteryUnrestricted,
                () => AlarmHostApi().openBatterySettings()),
          ],
          TextButton(
              onPressed: _refreshPermissions, child: const Text('Re-check')),
          const Divider(height: 32),
          ElevatedButton(
            onPressed: () => _addAlarmIn(const Duration(minutes: 1)),
            child: const Text('Ring in 1 minute'),
          ),
          ElevatedButton(
            onPressed: () => _addAlarmIn(const Duration(minutes: 2)),
            child: const Text('Ring in 2 minutes'),
          ),
          const Divider(height: 32),
          FutureBuilder(
            future: AlarmSyncService.instance.currentPlan(),
            builder: (context, snapshot) {
              final plan = snapshot.data;
              if (plan == null) return const Text('loading…');
              if (plan.isEmpty) return const Text('No alarms scheduled');
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final o in plan)
                    Text('#${o.alarmId} → ${o.fireAt.toLocal()}'),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow(this.label, this.granted, this.onFix);

  final String label;
  final bool granted;
  final VoidCallback onFix;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(granted ? Icons.check_circle : Icons.error,
            color: granted ? Colors.green : Colors.red, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(label)),
        if (!granted) TextButton(onPressed: onFix, child: const Text('Fix')),
      ],
    );
  }
}
