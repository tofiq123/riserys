import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// The Mono type scale. Geist for UI/display, Geist Mono for every numeral,
/// time and stat — the monospace numerals are the design's signature.
abstract final class RiseText {
  static const _ui = 'Geist';
  static const _mono = 'Geist Mono';

  static const TextStyle display = TextStyle(
    fontFamily: _ui,
    fontWeight: FontWeight.w600,
    fontSize: 26,
    height: 1.1,
    letterSpacing: -0.02 * 26,
    color: RiseColors.text,
  );

  static const TextStyle title = TextStyle(
    fontFamily: _ui,
    fontWeight: FontWeight.w600,
    fontSize: 16,
    letterSpacing: -0.01 * 16,
    color: RiseColors.text,
  );

  static const TextStyle body = TextStyle(
    fontFamily: _ui,
    fontWeight: FontWeight.w400,
    fontSize: 14.5,
    color: RiseColors.text,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: _ui,
    fontWeight: FontWeight.w400,
    fontSize: 12.5,
    color: RiseColors.textDim,
  );

  /// 11px uppercase semibold with 0.1em tracking. Callers uppercase the text.
  static const TextStyle sectionLabel = TextStyle(
    fontFamily: _ui,
    fontWeight: FontWeight.w600,
    fontSize: 11,
    letterSpacing: 1.1,
    color: RiseColors.textDim,
  );

  static TextStyle mono({
    double size = 15,
    FontWeight weight = FontWeight.w500,
    Color color = RiseColors.text,
    double? letterSpacing,
  }) =>
      TextStyle(
        fontFamily: _mono,
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
      );

  static const TextStyle monoDisplay = TextStyle(
    fontFamily: _mono,
    fontWeight: FontWeight.w500,
    fontSize: 56,
    color: RiseColors.text,
  );
}
