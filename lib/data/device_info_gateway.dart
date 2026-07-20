import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';

/// Abstracts device identification so UI (the Setup Guardian) is testable
/// without the platform channel. Production uses [NativeDeviceInfoGateway];
/// tests inject a fake returning a fixed manufacturer.
abstract interface class DeviceInfoGateway {
  /// The Android `Build.MANUFACTURER` (e.g. "samsung", "Xiaomi"), or null on
  /// non-Android platforms or if it cannot be read. Feeds [oemGuidanceFor].
  Future<String?> androidManufacturer();

  /// True on Android — the only platform with OEM battery-killer risk and the
  /// user-facing battery/exact-alarm/full-screen-intent toggles.
  bool get isAndroid;
}

class NativeDeviceInfoGateway implements DeviceInfoGateway {
  NativeDeviceInfoGateway();

  final DeviceInfoPlugin _plugin = DeviceInfoPlugin();

  @override
  bool get isAndroid => Platform.isAndroid;

  @override
  Future<String?> androidManufacturer() async {
    if (!Platform.isAndroid) return null;
    try {
      final info = await _plugin.androidInfo;
      return info.manufacturer;
    } catch (_) {
      // A plugin failure must never break the reliability dashboard — fall back
      // to generic guidance instead.
      return null;
    }
  }
}
