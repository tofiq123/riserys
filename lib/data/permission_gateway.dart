import 'native/alarm_api.g.dart';

/// Abstracts the native permission calls so UI is testable without the
/// platform channel. Production uses [NativePermissionGateway].
abstract interface class PermissionGateway {
  Future<AlarmPermissions> status();
  Future<void> requestNotifications();
  Future<void> openExactAlarm();
  Future<void> openFullScreenIntent();
  Future<void> openBattery();
}

class NativePermissionGateway implements PermissionGateway {
  const NativePermissionGateway();
  @override
  Future<AlarmPermissions> status() => AlarmHostApi().getPermissions();
  @override
  Future<void> requestNotifications() =>
      AlarmHostApi().requestNotificationPermission();
  @override
  Future<void> openExactAlarm() => AlarmHostApi().openExactAlarmSettings();
  @override
  Future<void> openFullScreenIntent() =>
      AlarmHostApi().openFullScreenIntentSettings();
  @override
  Future<void> openBattery() => AlarmHostApi().openBatterySettings();
}
