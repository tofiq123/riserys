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

  // RingActivity is a plain FlutterActivity: it runs this same main() in its
  // own engine while an alarm is audibly ringing (isLooping, no timeout) with
  // an ongoing/non-dismissible notification. If a throw here (a missing
  // documents directory, a SqliteException opening the db, a PlatformException
  // from the native reconcile call) stopped runApp() from ever being reached,
  // the ring UI — including its Dismiss button — would never render, and the
  // alarm would be unstoppable short of force-stop or reboot. So this must
  // never let an exception escape past this point.
  try {
    await AlarmSyncService.configureForApp();
    // Every launch re-arms the scheduler: OEMs and OS updates silently clear it.
    await AlarmSyncService.instance.reconcileNow();
  } catch (e, s) {
    debugPrint('Rise: startup reconcile failed: $e\n$s');
  }

  // AlarmSyncService.instance throws if configureForApp() itself failed
  // above (rather than reconcileNow() failing after configure succeeded).
  // Guard this second access too, so a startup failure already reported
  // above does not crash main() a second time before runApp() is reached.
  AlarmRepository? repository;
  try {
    repository = AlarmSyncService.instance.repository;
  } catch (e) {
    debugPrint('Rise: AlarmSyncService unavailable after startup failure: $e');
  }

  runApp(RiseApp(repository: repository));
}

class RiseApp extends StatefulWidget {
  const RiseApp({super.key, required this.repository});

  // Null when startup failed to configure the service (see main() above).
  // The home screen degrades visibly instead of the app crashing on a second
  // throw from AlarmSyncService.instance.
  final AlarmRepository? repository;

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
  /// This is the only path to DevRingPage (and its Dismiss button) on that
  /// cold start, so a thrown PlatformException here must not go unhandled:
  /// left unguarded, it would abort before _showRing ever runs and the
  /// ringing alarm would render no way to stop it.
  Future<void> _checkColdStartRing() async {
    try {
      final id = await AlarmHostApi().getRingingAlarmId();
      if (id != null) _showRing(id);
    } catch (e) {
      debugPrint('Rise: could not check for a cold-start ringing alarm: $e');
    }
  }

  void _showRing(int alarmId) {
    _navigatorKey.currentState?.push(MaterialPageRoute(
      builder: (_) => DevRingPage(alarmId: alarmId),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final repository = widget.repository;
    return MaterialApp(
      title: 'Rise',
      navigatorKey: _navigatorKey,
      home: repository == null
          ? const _StartupFailedPage()
          : DevHomePage(repository: repository),
    );
  }
}

/// Throwaway degrade-visibly screen shown when startup's configureForApp()
/// failed. Alarms already armed still ring — RingActivity runs its own
/// engine and DevRingPage's Dismiss does not depend on this repository — but
/// the home screen has no database to read or write until the app restarts.
class _StartupFailedPage extends StatelessWidget {
  const _StartupFailedPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.error_outline, size: 48),
              SizedBox(height: 16),
              Text(
                'Rise failed to start and could not reach the database.\n'
                'Already-armed alarms will still ring. Restart the app to '
                'try again.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FlutterApiImpl implements AlarmFlutterApi {
  _FlutterApiImpl({required this.onFired});

  final void Function(int alarmId) onFired;

  @override
  void onAlarmFired(int alarmId) => onFired(alarmId);
}
