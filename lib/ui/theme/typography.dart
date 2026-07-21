import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// The Mono type scale. Geist for UI/display, Geist Mono for every numeral,
/// time and stat — the monospace numerals are the design's signature.
///
/// These are getters (not `const`) because their `color` reads the active
/// [RiseColors] palette, which swaps between light and dark at runtime. The
/// non-colour metrics are unchanged from the original const styles.
abstract final class RiseText {
  static const _ui = 'Geist';
  static const _mono = 'Geist Mono';

  static TextStyle get display => TextStyle(
        fontFamily: _ui,
        fontWeight: FontWeight.w600,
        fontSize: 26,
        height: 1.1,
        letterSpacing: -0.02 * 26,
        color: RiseColors.text,
      );

  static TextStyle get title => TextStyle(
        fontFamily: _ui,
        fontWeight: FontWeight.w600,
        fontSize: 16,
        letterSpacing: -0.01 * 16,
        color: RiseColors.text,
      );

  static TextStyle get body => TextStyle(
        fontFamily: _ui,
        fontWeight: FontWeight.w400,
        fontSize: 14.5,
        color: RiseColors.text,
      );

  static TextStyle get caption => TextStyle(
        fontFamily: _ui,
        fontWeight: FontWeight.w400,
        fontSize: 12.5,
        color: RiseColors.textDim,
      );

  /// 11px uppercase semibold with 0.1em tracking. Callers uppercase the text.
  static TextStyle get sectionLabel => TextStyle(
        fontFamily: _ui,
        fontWeight: FontWeight.w600,
        fontSize: 11,
        letterSpacing: 1.1,
        color: RiseColors.textDim,
      );

  static TextStyle mono({
    double size = 15,
    FontWeight weight = FontWeight.w500,
    // Was `Color color = RiseColors.text`; the palette token is no longer const,
    // so the default moved into the body. Passing null keeps the old behaviour.
    Color? color,
    double? letterSpacing,
  }) =>
      TextStyle(
        fontFamily: _mono,
        fontSize: size,
        fontWeight: weight,
        color: color ?? RiseColors.text,
        letterSpacing: letterSpacing,
      );

  static TextStyle get monoDisplay => TextStyle(
        fontFamily: _mono,
        fontWeight: FontWeight.w500,
        fontSize: 56,
        color: RiseColors.text,
      );
}
