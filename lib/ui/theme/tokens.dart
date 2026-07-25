import 'package:flutter/widgets.dart';

/// The "Mono" theme. Two palettes back the same token names: [_light] (the
/// original, device-verified values — do not change without updating the spec)
/// and [_dark] (a carefully tuned near-black variant).
///
/// The colour tokens are getters that read the currently active palette
/// ([_current]). The app root calls [RiseColors.setPalette] with the resolved
/// brightness BEFORE it builds the widget tree each frame, so every widget that
/// reads these getters during its build sees the palette for the active theme.
/// A theme change rebuilds the root, which re-reads the getters below.
///
/// Because these are getters (not `const`), they cannot be used inside `const`
/// constructors — call sites that did so were de-`const`ed. [RiseRadii],
/// [RiseShadows] and [RiseSpacing] are theme-independent and remain `const`.
abstract final class RiseColors {
  /// The active palette. Defaults to [_light] so anything that reads a token
  /// before the root sets a palette (and every test that asserts a value) sees
  /// the original light values.
  static _RisePalette _current = _light;

  /// Swap the active palette for the resolved [brightness]. Called by the app
  /// root at the top of its build, before descendants read the tokens.
  static void setPalette(Brightness brightness) {
    _current = brightness == Brightness.dark ? _dark : _light;
  }

  /// The brightness of the active palette (for callers that need to branch,
  /// e.g. status-bar icon brightness).
  static Brightness get brightness =>
      identical(_current, _dark) ? Brightness.dark : Brightness.light;

  static Color get appBg => _current.appBg;
  static Color get card => _current.card;
  static Color get surface2 => _current.surface2;
  static Color get text => _current.text;
  static Color get textDim => _current.textDim;
  static Color get textFaint => _current.textFaint;
  static Color get border => _current.border;
  static Color get divider => _current.divider;
  static Color get primary => _current.primary;
  static Color get primaryText => _current.primaryText;
  static Color get accent => _current.accent;
  static Color get accentSoft => _current.accentSoft;
  static Color get danger => _current.danger;
  static Color get positive => _current.positive;
  static Color get waking => _current.waking;
  static Color get asleep => _current.asleep;

  /// The modal scrim behind every bottom sheet and dialog barrier. A theme-
  /// independent black alpha that dims correctly over both grounds, so every
  /// `showModalBottomSheet` passes `barrierColor: RiseColors.scrim` for one
  /// consistent focus depth. Flutter's default (`black54`) is heavier, which
  /// made un-styled sheets darker than the three that set a value explicitly.
  static const Color scrim = Color(0x66000000);

  /// Light palette — the original Mono spec values, byte-for-byte. Preserving
  /// these exactly keeps the (device-verified) light theme pixel-identical.
  static const _light = _RisePalette(
    appBg: Color(0xFFF4F4F5),
    card: Color(0xFFFFFFFF),
    surface2: Color(0xFFFAFAFA),
    text: Color(0xFF09090B),
    textDim: Color(0xFF71717A),
    textFaint: Color(0xFFA1A1AA),
    border: Color(0xFFE4E4E7),
    divider: Color(0xFFF0F0F1),
    primary: Color(0xFF18181B),
    primaryText: Color(0xFFFAFAFA),
    accent: Color(0xFF18181B),
    accentSoft: Color(0xFFF4F4F5),
    danger: Color(0xFFEF4444),
    positive: Color(0xFF22C55E),
    waking: Color(0xFFF59E0B),
    asleep: Color(0xFF6366F1), // indigo — presumed sleeping
  );

  /// Dark palette — a tuned near-black variant (not a naive inversion). Near-
  /// black grounds, light ink, subtle borders, inverted primary (light-on-dark
  /// buttons), and semantic hues brightened for legibility on dark.
  static const _dark = _RisePalette(
    appBg: Color(0xFF09090B),
    card: Color(0xFF18181B),
    surface2: Color(0xFF131316),
    text: Color(0xFFFAFAFA),
    textDim: Color(0xFFA1A1AA),
    textFaint: Color(0xFF71717A),
    border: Color(0xFF27272A),
    divider: Color(0xFF202024),
    primary: Color(0xFFFAFAFA),
    primaryText: Color(0xFF18181B),
    accent: Color(0xFFFAFAFA),
    accentSoft: Color(0xFF27272A),
    danger: Color(0xFFF87171),
    positive: Color(0xFF4ADE80),
    waking: Color(0xFFFBBF24),
    asleep: Color(0xFF818CF8), // indigo — presumed sleeping
  );
}

/// An immutable set of colour tokens for one theme. Held privately by
/// [RiseColors]; swapped wholesale by [RiseColors.setPalette].
class _RisePalette {
  const _RisePalette({
    required this.appBg,
    required this.card,
    required this.surface2,
    required this.text,
    required this.textDim,
    required this.textFaint,
    required this.border,
    required this.divider,
    required this.primary,
    required this.primaryText,
    required this.accent,
    required this.accentSoft,
    required this.danger,
    required this.positive,
    required this.waking,
    required this.asleep,
  });

  final Color appBg;
  final Color card;
  final Color surface2;
  final Color text;
  final Color textDim;
  final Color textFaint;
  final Color border;
  final Color divider;
  final Color primary;
  final Color primaryText;
  final Color accent;
  final Color accentSoft;
  final Color danger;
  final Color positive;
  final Color waking;
  final Color asleep;
}

abstract final class RiseRadii {
  static const double sm = 9;
  static const double base = 13;
  static const double lg = 18;
  static const double pill = 999;
}

abstract final class RiseShadows {
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x0D18181B), offset: Offset(0, 1), blurRadius: 2),
    BoxShadow(color: Color(0x0A18181B), offset: Offset(0, 1), blurRadius: 3),
  ];
  static const List<BoxShadow> primary = [
    BoxShadow(color: Color(0x1A000000), offset: Offset(0, 1), blurRadius: 2),
  ];
}

abstract final class RiseSpacing {
  static const double screen = 20;
  static const double cardPad = 14;
  static const double gap = 11;
}
