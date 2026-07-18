import 'package:flutter/widgets.dart';

/// Parses a profile `avatar_color` hex string ('#RRGGBB') to a [Color],
/// falling back to a default on malformed input (never throws).
Color avatarColorFromHex(String hex) {
  final cleaned = hex.replaceFirst('#', '');
  final value =
      int.tryParse(cleaned.length == 6 ? 'FF$cleaned' : cleaned, radix: 16);
  return value == null ? const Color(0xFF7C9CF4) : Color(value);
}
