import 'package:flutter/material.dart';

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
                await AlarmHostApi().stopRinging(alarmId);
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
