import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/ui/theme/tokens.dart';
import 'package:rise/ui/theme/typography.dart';

void main() {
  test('display uses Geist 600 with tight tracking', () {
    final s = RiseText.display;
    expect(s.fontFamily, 'Geist');
    expect(s.fontWeight, FontWeight.w600);
    expect(s.letterSpacing, closeTo(-0.02 * (s.fontSize ?? 0), 0.5));
  });

  test('mono uses Geist Mono and honors overrides', () {
    final s = RiseText.mono(size: 46, weight: FontWeight.w500, color: RiseColors.text);
    expect(s.fontFamily, 'Geist Mono');
    expect(s.fontSize, 46);
    expect(s.fontWeight, FontWeight.w500);
    expect(s.color, RiseColors.text);
  });

  test('section label is 11px semibold with wide tracking', () {
    final s = RiseText.sectionLabel;
    expect(s.fontSize, 11);
    expect(s.fontWeight, FontWeight.w600);
    expect(s.letterSpacing, closeTo(1.1, 0.2)); // ~0.1em of 11px
    expect(s.color, RiseColors.textDim);
  });
}
