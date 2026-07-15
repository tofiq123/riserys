import 'package:flutter/material.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import 'data/alarm_sync_service.dart';
import 'data/local/alarm_repository.dart';
import 'data/native/alarm_api.g.dart';
import 'ui/dev_home_page.dart';
import 'ui/dev_ring_page.dart';

/// Headless entrypoint invoked by Android's BootReceiver after boot, app
/// replacement, or a clock change. Re-arms the scheduler from the local
/// database and recovers any alarm missed while the device was off.
@pragma('vm:entry-point')
Future<void> reconcileEntrypoint() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  try {
    await AlarmSyncService.configureForApp();
    await AlarmSyncService.instance.reconcileNow(recoverMissed: true);
  } finally {
    // Let the platform tear down the headless engine that ran this, even if
    // reconcile above threw — otherwise a crash leaks the engine forever.
    await AlarmHostApi().reconcileFinished();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  await AlarmSyncService.configureForApp();

  // Every launch re-arms the scheduler: OEMs and OS updates silently clear it.
  await AlarmSyncService.instance.reconcileNow();

  runApp(RiseApp(repository: AlarmSyncService.instance.repository));
}

class RiseApp extends StatefulWidget {
  const RiseApp({super.key, required this.repository});

  final AlarmRepository repository;

  @override
  State<RiseApp> createState() => _RiseAppState();
}

class _RiseAppState extends State<RiseApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    // Engine already alive when an alarm fires.
    AlarmFlutterApi.setUp(_FlutterApiImpl(onFired: _showRing));
    _checkColdStartRing();
  }

  /// Cold start: RingActivity launched the engine from scratch, so no
  /// onAlarmFired callback ever arrives — ask the platform what is ringing.
  Future<void> _checkColdStartRing() async {
    final id = await AlarmHostApi().getRingingAlarmId();
    if (id != null) _showRing(id);
  }

  void _showRing(int alarmId) {
    _navigatorKey.currentState?.push(MaterialPageRoute(
      builder: (_) => DevRingPage(alarmId: alarmId),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rise',
      navigatorKey: _navigatorKey,
      home: DevHomePage(repository: widget.repository),
    );
  }
}

class _FlutterApiImpl implements AlarmFlutterApi {
  _FlutterApiImpl({required this.onFired});

  final void Function(int alarmId) onFired;

  @override
  void onAlarmFired(int alarmId) => onFired(alarmId);
}
