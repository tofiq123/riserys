import 'package:flutter/foundation.dart';
import 'package:screen_brightness/screen_brightness.dart';

/// A thin, injectable seam over the device's *application* screen brightness,
/// used by the ring screen's opt-in sunrise wake to gently brighten the display
/// while the alarm rings and to restore the system brightness on teardown.
///
/// Every operation is best-effort: a missing plugin or platform failure is
/// swallowed so a brightness hiccup can never crash the ring or block a
/// dismissal. The ring screen only ever calls these when the sunrise setting is
/// on, and tests inject a fake — so no real plugin channel is touched headless.
abstract class BrightnessController {
  /// Sets the application screen brightness to [value] (clamped to 0.0–1.0).
  Future<void> setBrightness(double value);

  /// Restores the system-managed brightness, undoing any [setBrightness].
  Future<void> restore();
}

/// Production [BrightnessController] backed by the `screen_brightness` plugin.
/// `const`-constructible and side-effect-free until a method is invoked, so it
/// is a safe default even where the plugin is unavailable (headless/desktop):
/// nothing runs unless the ring actually turns the sunrise on.
class ScreenBrightnessController implements BrightnessController {
  const ScreenBrightnessController();

  @override
  Future<void> setBrightness(double value) async {
    try {
      await ScreenBrightness().setApplicationScreenBrightness(
        value.clamp(0.0, 1.0),
      );
    } catch (e) {
      debugPrint('Rise: screen-brightness set failed (ignored): $e');
    }
  }

  @override
  Future<void> restore() async {
    try {
      await ScreenBrightness().resetApplicationScreenBrightness();
    } catch (e) {
      debugPrint('Rise: screen-brightness restore failed (ignored): $e');
    }
  }
}

/// A [BrightnessController] that does nothing — for previews/tests and any
/// caller that wants the sunrise visuals without touching the hardware.
class NoopBrightnessController implements BrightnessController {
  const NoopBrightnessController();

  @override
  Future<void> setBrightness(double value) async {}

  @override
  Future<void> restore() async {}
}
