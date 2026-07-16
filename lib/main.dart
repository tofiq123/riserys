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

class _RiseAppState extends State<RiseApp> with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();

  // The alarm id currently shown on a pushed DevRingPage, or null if none is
  // showing. Tracked so a re-check can tell "the same alarm is still
  // ringing" (do nothing) apart from "a different alarm has taken over" (
  // replace the page) apart from "nothing is ringing any more" (pop). Kept in
  // sync with reality by the `.then` callback in _showRing below, which fires
  // whenever the pushed route is popped for *any* reason — our own pop, the
  // Dismiss button's own pop, or the user backing out — not just when this
  // class does the popping.
  int? _shownRingId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkColdStartRing();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // RingActivity is android:launchMode="singleInstance": a second alarm
    // firing while it is still showing does not recreate it, so initState
    // above never runs again and would otherwise never learn about the new
    // alarm. Resuming is the one signal available in both that case (the
    // reused activity is brought back to the foreground, which always goes
    // through onResume) and the general case of returning to the app while
    // an alarm rings.
    if (state == AppLifecycleState.resumed) _checkColdStartRing();
  }

  /// Cold start: RingActivity launched the engine from scratch, so nothing
  /// else ever tells Dart an alarm is ringing — ask the platform directly.
  /// Also re-run on every resume (see didChangeAppLifecycleState) to catch a
  /// second alarm taking over an already-running engine. Either way, a
  /// thrown PlatformException here must not go unhandled: left unguarded, it
  /// would stop the ring screen from ever appearing or updating, and the
  /// ringing alarm would render no way to stop it.
  Future<void> _checkColdStartRing() async {
    int? id;
    try {
      id = await AlarmHostApi().getRingingAlarmId();
    } catch (e) {
      debugPrint('Rise: could not check for a ringing alarm: $e');
      return;
    }
    _reconcileRingScreen(id);
  }

  /// Makes the ring screen match what the platform says is ringing.
  void _reconcileRingScreen(int? id) {
    if (id == _shownRingId) return; // Already showing the right thing.

    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;

    if (id == null) {
      // Nothing is ringing any more (e.g. the service died some other way).
      // Don't leave a dead ring screen whose Dismiss button does nothing.
      _shownRingId = null;
      navigator.maybePop();
      return;
    }

    if (_shownRingId == null) {
      _showRing(id, replace: false);
    } else {
      // A different alarm has taken over the ring service: replace rather
      // than stack a second ring page on top of the stale one.
      _showRing(id, replace: true);
    }
  }

  void _showRing(int alarmId, {required bool replace}) {
    _shownRingId = alarmId;
    final route = MaterialPageRoute<void>(
      builder: (_) => DevRingPage(alarmId: alarmId),
    );
    final navigator = _navigatorKey.currentState!;
    final future =
        replace ? navigator.pushReplacement(route) : navigator.push(route);
    future.then((_) {
      if (_shownRingId == alarmId) _shownRingId = null;
    });
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
