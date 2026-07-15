import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/data/native/alarm_api.g.dart',
  kotlinOut: 'android/app/src/main/kotlin/com/riseapp/rise/AlarmApi.g.kt',
  kotlinOptions: KotlinOptions(package: 'com.riseapp.rise'),
  swiftOut: 'ios/Runner/AlarmApi.g.swift',
  dartPackageName: 'rise',
))

/// One concrete future firing, as handed to the platform scheduler.
/// [fireAtEpochMs] is absolute UTC milliseconds — all wall-clock and DST
/// reasoning happens in Dart before this crosses the channel.
class NativeAlarm {
  NativeAlarm({
    required this.id,
    required this.fireAtEpochMs,
    required this.label,
    required this.soundAsset,
    required this.vibrate,
  });

  int id;
  int fireAtEpochMs;
  String label;
  String soundAsset;
  bool vibrate;
}

/// Everything that can silently stop Rise from ringing. Surfaced by the Setup
/// Guardian; re-checked on every app launch because OEMs revert these.
class AlarmPermissions {
  AlarmPermissions({
    required this.notifications,
    required this.exactAlarm,
    required this.fullScreenIntent,
    required this.batteryUnrestricted,
  });

  bool notifications;
  bool exactAlarm;
  bool fullScreenIntent;
  bool batteryUnrestricted;
}

@HostApi()
abstract class AlarmHostApi {
  /// Replaces the platform's entire scheduled set with [alarms].
  void reconcile(List<NativeAlarm> alarms);

  /// Rings [alarm] immediately without touching the scheduled set.
  ///
  /// Missed-alarm recovery must never go through [reconcile]: reconcile is a
  /// full replace, so recovering one alarm that way would silently cancel
  /// every other alarm the user has set.
  void ringNow(NativeAlarm alarm);

  void cancelAll();

  AlarmPermissions getPermissions();

  void requestNotificationPermission();
  void openExactAlarmSettings();
  void openBatterySettings();
  void openFullScreenIntentSettings();

  /// The alarm id currently ringing, or null if nothing is ringing.
  ///
  /// Safe to call repeatedly — this peeks, it does not clear state. The id
  /// stays valid for the whole ring so [stopRinging] can verify it is
  /// stopping the alarm it was asked to stop. Needed at cold start: the
  /// ringing activity can launch the Flutter engine from scratch, in which
  /// case no onAlarmFired callback ever arrives.
  int? getRingingAlarmId();

  void stopRinging(int alarmId);

  /// Signals that a headless reconcile (boot, app update, clock change) has
  /// finished, so the platform can tear down the engine that ran it.
  /// Harmless to call from a normal app engine, where it is a no-op.
  void reconcileFinished();
}

@FlutterApi()
abstract class AlarmFlutterApi {
  /// Fired when an alarm starts ringing while the engine is already alive.
  void onAlarmFired(int alarmId);
}
