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
    required this.hour,
    required this.minute,
    required this.weekdays,
  });

  int id;
  int fireAtEpochMs;
  String label;
  String soundAsset;
  bool vibrate;

  /// Recurrence pattern, for platforms that own recurrence natively (iOS
  /// AlarmKit / UNCalendar). [weekdays] uses 0=Sun…6=Sat; empty = one-shot.
  /// Android ignores these and schedules the single [fireAtEpochMs] instant.
  int hour;
  int minute;
  List<int> weekdays;
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

/// What a platform's alarm engine can do. iOS 16–25 has no system-alarm API,
/// so the sync service falls back to a notification burst there.
class PlatformCapabilities {
  PlatformCapabilities({required this.supportsSystemAlarms});

  /// True when the platform can schedule true system alarms (Android
  /// AlarmManager always; iOS only on 26+ via AlarmKit). False on iOS 16–25,
  /// where [AlarmHostApi.reconcileNotifications] is used instead.
  bool supportsSystemAlarms;
}

/// One scheduled local notification in the iOS 16–25 fallback burst. The Dart
/// budget allocator produces these; only the iOS notification engine consumes
/// them. Android reports [PlatformCapabilities.supportsSystemAlarms] true and
/// never receives these.
class NotificationRequest {
  NotificationRequest({
    required this.alarmId,
    required this.fireAtEpochMs,
    required this.label,
    required this.sound,
    required this.burstIndex,
    required this.burstTotal,
  });

  int alarmId;
  int fireAtEpochMs;
  String label;
  String sound;
  int burstIndex;
  int burstTotal;
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
  /// stopping the alarm it was asked to stop. This is the *only* way Dart
  /// learns what is ringing — there is no push channel the other way — so
  /// callers must poll it: at cold start (the ringing activity can launch
  /// the Flutter engine from scratch) and again on every app resume (the
  /// ringing activity is `singleInstance`, so a second alarm taking over an
  /// already-running engine delivers onNewIntent natively with no signal
  /// that reaches Dart on its own).
  int? getRingingAlarmId();

  void stopRinging(int alarmId);

  /// Signals that a headless reconcile (boot, app update, clock change) has
  /// finished, so the platform can tear down the engine that ran it.
  /// Harmless to call from a normal app engine, where it is a no-op.
  void reconcileFinished();

  /// What this platform's alarm engine supports. Queried by the sync service
  /// to choose between system alarms and the notification-burst fallback.
  PlatformCapabilities capabilities();

  /// Replaces the platform's entire scheduled notification set (the iOS 16–25
  /// fallback). A full replace, like [reconcile]. No-op on Android.
  void reconcileNotifications(List<NotificationRequest> requests);
}
