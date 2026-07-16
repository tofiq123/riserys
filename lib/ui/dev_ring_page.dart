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
                // Stop the alarm first: nothing gates this on the dismissal
                // being recorded, and the write below can block for seconds
                // under SQLite contention (busy_timeout = 5000) if another
                // engine is mid-write. A user tapping Dismiss must silence
                // the alarm immediately, not after the database is reached.
                //
                // AlarmSyncService.instance throws if configureForApp()
                // failed at startup (see main.dart). stopRinging must still
                // run even then: it talks straight to AlarmHostApi() and
                // does not depend on the Dart-side service, so it is pulled
                // out of the service calls' try/catch rather than skipped
                // along with them — a ringing alarm must always be
                // stoppable, even with no database reachable.
                await AlarmHostApi().stopRinging(alarmId);

                try {
                  await AlarmSyncService.instance.repository
                      .recordDismissed(alarmId, DateTime.now().toUtc());
                  // Must follow recordDismissed so the reconcile sees a
                  // disabled one-shot, rather than re-arming it for tomorrow.
                  await AlarmSyncService.instance.reconcileNow();
                } catch (e) {
                  debugPrint(
                      'Rise: could not record dismissal for alarm $alarmId: $e');
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
