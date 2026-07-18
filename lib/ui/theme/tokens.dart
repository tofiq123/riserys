import 'package:flutter/widgets.dart';

/// The "Mono" theme — the only theme in v1. Values are the exact hex from the
/// design spec; do not adjust them without updating the spec.
abstract final class RiseColors {
  static const appBg = Color(0xFFF4F4F5);
  static const card = Color(0xFFFFFFFF);
  static const surface2 = Color(0xFFFAFAFA);
  static const text = Color(0xFF09090B);
  static const textDim = Color(0xFF71717A);
  static const textFaint = Color(0xFFA1A1AA);
  static const border = Color(0xFFE4E4E7);
  static const divider = Color(0xFFF0F0F1);
  static const primary = Color(0xFF18181B);
  static const primaryText = Color(0xFFFAFAFA);
  static const accent = Color(0xFF18181B);
  static const accentSoft = Color(0xFFF4F4F5);
  static const danger = Color(0xFFEF4444);
  static const positive = Color(0xFF22C55E);
  static const waking = Color(0xFFF59E0B);
  static const asleep = Color(0xFF6366F1); // indigo — presumed sleeping
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
