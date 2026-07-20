// Reproducible source-icon generator for the Rise launcher icon.
//
// Draws a minimal, on-brand "Rise" mark — a warm sunrise (a rising sun over a
// horizon) on a deep near-black field. The palette is taken straight from the
// Mono theme in lib/ui/theme/tokens.dart: the warm amber "waking" accent
// (#F59E0B) rising against the near-black "primary" (#18181B). Two PNGs are
// written:
//
//   assets/icon/rise_icon.png             1024x1024, opaque — the master icon.
//                                         Used for iOS and as the
//                                         flutter_launcher_icons base image.
//   assets/icon/rise_icon_foreground.png  1024x1024, transparent — the Android
//                                         adaptive foreground. The mark is kept
//                                         well inside the central safe zone so
//                                         the launcher's circle/squircle mask
//                                         never clips it; the ground is left
//                                         transparent because the adaptive
//                                         background layer (a solid brand color)
//                                         shows through as the horizon.
//
// Run:  dart run tool/gen_icon.dart
//
// Keep this in sync with lib/ui/theme/tokens.dart if the brand palette changes.

import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

const int _size = 1024;

/// A straight-alpha RGB triple in 0..255 space, stored as doubles so gradients
/// and compositing stay smooth before the final round to bytes.
class _Rgb {
  const _Rgb(this.r, this.g, this.b);
  final double r, g, b;
}

_Rgb _hex(int v) =>
    _Rgb(((v >> 16) & 0xFF).toDouble(), ((v >> 8) & 0xFF).toDouble(), (v & 0xFF).toDouble());

// Brand palette (from lib/ui/theme/tokens.dart).
final _skyTop = _hex(0x0A0A0C); // near-black, faintly warm-neutral
final _skyHorizon = _hex(0x1A130B); // subtle warm shift toward the horizon
final _ground = _hex(0x18181B); // RiseColors.primary — matches adaptive bg
final _sunTop = _hex(0xFCD34D); // light amber crown
final _sunBottom = _hex(0xF59E0B); // RiseColors.waking — warm amber
final _glow = _hex(0xF59E0B);

_Rgb _lerp(_Rgb a, _Rgb b, double t) {
  final u = t.clamp(0.0, 1.0);
  return _Rgb(a.r + (b.r - a.r) * u, a.g + (b.g - a.g) * u, a.b + (b.b - a.b) * u);
}

/// Straight-alpha "src over dst". Returns the composited color and its alpha.
({_Rgb c, double a}) _over(_Rgb dstC, double dstA, _Rgb srcC, double srcA) {
  final s = srcA.clamp(0.0, 1.0);
  final outA = s + dstA * (1 - s);
  if (outA <= 0.0) return (c: const _Rgb(0, 0, 0), a: 0.0);
  final r = (srcC.r * s + dstC.r * dstA * (1 - s)) / outA;
  final g = (srcC.g * s + dstC.g * dstA * (1 - s)) / outA;
  final b = (srcC.b * s + dstC.b * dstA * (1 - s)) / outA;
  return (c: _Rgb(r, g, b), a: outA);
}

/// Renders one variant of the mark.
///
/// When [opaqueBase] is true the whole canvas is painted (sky gradient + solid
/// ground) for the master icon. When false only the lit mark (glow + sun +
/// horizon streak) is drawn on transparency for the adaptive foreground.
img.Image _render({
  required bool opaqueBase,
  required double horizonY,
  required double sunR,
  required double glowR,
}) {
  final image = img.Image(width: _size, height: _size, numChannels: 4);
  const cx = _size / 2.0;
  final cy = horizonY; // sun centered on the horizon => a rising semicircle

  for (var y = 0; y < _size; y++) {
    final aboveHorizon = y <= horizonY;
    for (var x = 0; x < _size; x++) {
      // Base layer.
      _Rgb color;
      double alpha;
      if (opaqueBase) {
        color = aboveHorizon ? _lerp(_skyTop, _skyHorizon, y / horizonY) : _ground;
        alpha = 1.0;
      } else {
        color = const _Rgb(0, 0, 0);
        alpha = 0.0;
      }

      if (aboveHorizon) {
        final dx = x - cx;
        final dy = y - cy;
        final dist = math.sqrt(dx * dx + dy * dy);

        // Soft radial glow.
        final gT = (1.0 - dist / glowR).clamp(0.0, 1.0);
        final glowA = gT * gT * 0.55;
        if (glowA > 0) {
          final r = _over(color, alpha, _glow, glowA);
          color = r.c;
          alpha = r.a;
        }

        // Soft warm horizon streak, extent scaled to the sun.
        final band = math.exp(-(dy * dy) / (2 * 1.4 * 1.4));
        final reach = (1.0 - (dx.abs() / (sunR * 2.4))).clamp(0.0, 1.0);
        final lineA = band * reach * 0.40;
        if (lineA > 0) {
          final r = _over(color, alpha, _glow, lineA);
          color = r.c;
          alpha = r.a;
        }

        // Sun disc with a 1px anti-aliased edge.
        final coverage = (sunR - dist + 0.5).clamp(0.0, 1.0);
        if (coverage > 0) {
          final sunT = ((y - (cy - sunR)) / sunR).clamp(0.0, 1.0);
          final sun = _lerp(_sunTop, _sunBottom, sunT);
          final r = _over(color, alpha, sun, coverage);
          color = r.c;
          alpha = r.a;
        }
      }

      image.setPixelRgba(
        x,
        y,
        color.r.round().clamp(0, 255),
        color.g.round().clamp(0, 255),
        color.b.round().clamp(0, 255),
        (alpha * 255).round().clamp(0, 255),
      );
    }
  }
  return image;
}

void _write(String path, img.Image image) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(img.encodePng(image));
  stdout.writeln('wrote $path (${image.width}x${image.height})');
}

void main() {
  // Master icon: sun a bit low, full-bleed field.
  _write(
    'assets/icon/rise_icon.png',
    _render(opaqueBase: true, horizonY: 662, sunR: 232, glowR: 470),
  );

  // Adaptive foreground: the same mark on transparency, full-bleed. The
  // launcher-icons generator already wraps this in a 16% safe-zone inset, so
  // filling the canvas here keeps the Android mark the same visual weight as
  // the iOS master rather than doubling up the padding.
  _write(
    'assets/icon/rise_icon_foreground.png',
    _render(opaqueBase: false, horizonY: 662, sunR: 232, glowR: 470),
  );
}
