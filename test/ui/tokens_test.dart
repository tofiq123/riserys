import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/ui/theme/tokens.dart';

void main() {
  test('core colors match the Mono spec hex values', () {
    expect(RiseColors.appBg, const Color(0xFFF4F4F5));
    expect(RiseColors.card, const Color(0xFFFFFFFF));
    expect(RiseColors.text, const Color(0xFF09090B));
    expect(RiseColors.textDim, const Color(0xFF71717A));
    expect(RiseColors.primary, const Color(0xFF18181B));
    expect(RiseColors.primaryText, const Color(0xFFFAFAFA));
    expect(RiseColors.danger, const Color(0xFFEF4444));
    expect(RiseColors.positive, const Color(0xFF22C55E));
    expect(RiseColors.waking, const Color(0xFFF59E0B));
  });

  test('radii match the spec', () {
    expect(RiseRadii.sm, 9);
    expect(RiseRadii.base, 13);
    expect(RiseRadii.lg, 18);
    expect(RiseRadii.pill, 999);
  });

  test('card shadow is the two-layer spec shadow', () {
    expect(RiseShadows.card, hasLength(2));
    expect(RiseShadows.card.first.blurRadius, 2);
    expect(RiseShadows.card.last.blurRadius, 3);
  });
}
