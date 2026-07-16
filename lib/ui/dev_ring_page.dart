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
                //
                // AlarmSyncService.instance throws if configureForApp()
                // failed at startup (see main.dart). stopRinging must still
                // run even then: it talks straight to AlarmHostApi() and
                // does not depend on the Dart-side service, so it is pulled
                // out of the service calls' try/catch rather than skipped
                // along with them — a ringing alarm must always be
                // stoppable, even with no database reachable.
                try {
                  await AlarmSyncService.instance.repository
                      .recordDismissed(alarmId, DateTime.now().toUtc());
                } catch (e) {
                  debugPrint(
                      'Rise: could not record dismissal for alarm $alarmId: $e');
                }

                await AlarmHostApi().stopRinging(alarmId);

                try {
                  await AlarmSyncService.instance.reconcileNow();
                } catch (e) {
                  debugPrint(
                      'Rise: could not reconcile after dismissing alarm $alarmId: $e');
                }

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
