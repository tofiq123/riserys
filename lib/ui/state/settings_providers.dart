import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_settings.dart';

/// The app's settings store. main() overrides this with the instance loaded at
/// startup; tests override it with an AppSettings over mock preferences.
final appSettingsProvider = Provider<AppSettings>((ref) {
  throw UnimplementedError('appSettingsProvider must be overridden in main()');
});
