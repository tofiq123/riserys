import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:rise/domain/photo_match.dart';

/// Encodes a solid [gray]-value square as PNG bytes so the full
/// decode→resize→hash pipeline can be exercised headlessly.
Uint8List _solidPng(int gray, {int size = 32}) {
  final image = img.Image(width: size, height: size);
  img.fill(image, color: img.ColorRgb8(gray, gray, gray));
  return img.encodePng(image);
}

/// A vertical split: left half [a], right half [b]. Produces a hash whose bits
/// depend on the per-pixel comparison to the mean.
Uint8List _splitPng(int a, int b, {int size = 32}) {
  final image = img.Image(width: size, height: size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final v = x < size ~/ 2 ? a : b;
      image.setPixelRgb(x, y, v, v, v);
    }
  }
  return img.encodePng(image);
}

void main() {
  group('averageHashFromGray', () {
    test('produces a 16-char hex string of the right length', () {
      final hash = averageHashFromGray(List<int>.filled(kAHashBits, 128));
      expect(hash.length, kAHashHexLen);
      expect(isValidHash(hash), isTrue);
    });

    test('rejects the wrong sample count', () {
      expect(() => averageHashFromGray(const [1, 2, 3]), throwsArgumentError);
    });

    test('a left/right brightness split hashes to half set bits', () {
      // Left 8 columns dark (0), right 8 bright (255): every bright pixel is
      // >= the mean and every dark one below it -> exactly 32 set bits.
      final gray = <int>[];
      for (var y = 0; y < kAHashSize; y++) {
        for (var x = 0; x < kAHashSize; x++) {
          gray.add(x < kAHashSize ~/ 2 ? 0 : 255);
        }
      }
      final hash = averageHashFromGray(gray);
      final ones = hammingDistanceHex(hash, '0000000000000000');
      expect(ones, 32);
    });
  });

  group('hammingDistanceHex', () {
    test('identical hashes have distance 0', () {
      expect(hammingDistanceHex('ffffffffffffffff', 'ffffffffffffffff'), 0);
    });

    test('all bits flipped is the full 64', () {
      expect(hammingDistanceHex('0000000000000000', 'ffffffffffffffff'), 64);
    });

    test('counts single differing bits', () {
      expect(hammingDistanceHex('0000000000000000', '0000000000000001'), 1);
      expect(hammingDistanceHex('0000000000000000', '0000000000000003'), 2);
    });

    test('throws on a length mismatch', () {
      expect(() => hammingDistanceHex('ff', 'ffff'), throwsArgumentError);
    });
  });

  group('isValidHash', () {
    test('accepts exactly 16 hex chars, any case', () {
      expect(isValidHash('0123456789abcdef'), isTrue);
      expect(isValidHash('0123456789ABCDEF'), isTrue);
    });
    test('rejects wrong length or non-hex', () {
      expect(isValidHash(''), isFalse);
      expect(isValidHash('abc'), isFalse);
      expect(isValidHash('0123456789abcdeg'), isFalse); // g is not hex
      expect(isValidHash('a-stray-qr-payload'), isFalse);
    });
  });

  group('photoMatches (pure decision)', () {
    test('an identical hash passes (well within threshold)', () {
      const h = '0f0f0f0f0f0f0f0f';
      expect(photoMatches(h, h), isTrue);
    });

    test('a wildly different hash fails', () {
      expect(photoMatches('0000000000000000', 'ffffffffffffffff'), isFalse);
    });

    test('a small difference under the lenient threshold still passes', () {
      // 4 bits apart — comfortably under kPhotoMatchThreshold (20).
      expect(photoMatches('0000000000000000', '000000000000000f'), isTrue);
    });

    test('a null/empty/whitespace reference accepts ANY photo (never a trap)',
        () {
      expect(photoMatches(null, 'ffffffffffffffff'), isTrue);
      expect(photoMatches('', 'ffffffffffffffff'), isTrue);
      expect(photoMatches('   ', 'ffffffffffffffff'), isTrue);
    });

    test('a malformed reference (e.g. stray QR payload) accepts any photo', () {
      expect(photoMatches('not-a-hash', 'ffffffffffffffff'), isTrue);
    });

    test('an unreadable candidate against a real reference is a miss', () {
      expect(photoMatches('0000000000000000', ''), isFalse);
      expect(photoMatches('0000000000000000', 'garbage'), isFalse);
    });

    test('the threshold is adjustable', () {
      // 4 bits apart: fails a strict 3-bit budget, passes a 4-bit one.
      expect(photoMatches('0000000000000000', '000000000000000f', threshold: 3),
          isFalse);
      expect(photoMatches('0000000000000000', '000000000000000f', threshold: 4),
          isTrue);
    });
  });

  group('averageHashOfImageBytes (full decode pipeline)', () {
    test('returns null for undecodable bytes', () {
      expect(averageHashOfImageBytes(Uint8List.fromList([1, 2, 3, 4])), isNull);
    });

    test('the same image hashes identically -> matches itself', () {
      final bytes = _splitPng(20, 220);
      final a = averageHashOfImageBytes(bytes)!;
      final b = averageHashOfImageBytes(bytes)!;
      expect(a, b);
      expect(photoMatches(a, b), isTrue);
    });

    test('a near-identical photo (slightly brighter) still matches', () {
      // Same composition, mild global brightness change — aHash is robust to it
      // because the per-pixel vs-mean pattern is preserved.
      final ref = averageHashOfImageBytes(_splitPng(20, 220))!;
      final shot = averageHashOfImageBytes(_splitPng(40, 240))!;
      expect(photoMatches(ref, shot), isTrue);
    });

    test('a very different scene does not match', () {
      // Uniform dark vs a bright-with-dark-corner scene: distinct fingerprints.
      final ref = averageHashOfImageBytes(_solidPng(10))!;
      final other = averageHashOfImageBytes(_splitPng(0, 255))!;
      expect(photoMatches(ref, other), isFalse);
    });
  });
}
