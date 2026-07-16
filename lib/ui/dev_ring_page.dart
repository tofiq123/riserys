import 'package:flutter/material.dart';

import '../data/alarm_sync_service.dart';
import '../data/native/alarm_api.g.dart';

/// Throwaway ringing screen. Plan 3 replaces this with the designed ringing
/// overlay and Plan 4 adds missions.
class DevRingPage extends StatelessWidget {
  const DevRingPage({super.key, required this.alarmId});

  final int alarmId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.alarm, size: 96),
            const SizedBox(height: 24),
            Text('Alarm $alarmId is ringing',
                style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 48),
            FilledButton(
              onPressed: () async {
                // Order matters: record the dismissal (and disable a one-shot
                // alarm) before stopping the sound, then reconcile so a
                // disabled one-shot is actually disarmed rather than re-armed
                // for tomorrow on the next boot/edit-triggered reconcile.
                await AlarmSyncService.instance.repository
                    .recordDismissed(alarmId, DateTime.now().toUtc());
                await AlarmHostApi().stopRinging(alarmId);
                await AlarmSyncService.instance.reconcileNow();
                if (context.mounted) Navigator.of(context).maybePop();
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                child: Text('Dismiss'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
