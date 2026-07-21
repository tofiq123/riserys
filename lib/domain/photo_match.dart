import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Average-hash (aHash) perceptual hashing for the photo-match dismiss mission.
///
/// The reference photo captured at setup and the photo taken at ring time are
/// each reduced to a compact 64-bit fingerprint. Two photos of the *same* spot
/// — even from a slightly different angle or under different light — produce
/// fingerprints differing in only a handful of bits, while a completely
/// different scene differs in ~half its bits. Dismissal compares the two with a
/// lenient Hamming threshold ([kPhotoMatchThreshold]) — deliberately favouring
/// NOT trapping the user over strict matching.
///
/// Everything here is pure Dart (the `image` decode is deterministic), so the
/// hashing, distance and pass/fail decision are all headlessly unit-tested. The
/// camera capture that produces the bytes is the only device-verify part.

/// Side length of the downscaled grayscale grid; 8×8 = 64 pixels = a 64-bit hash.
const int kAHashSize = 8;

/// Number of bits in an average hash.
const int kAHashBits = kAHashSize * kAHashSize; // 64

/// Length of the hex string that encodes a [kAHashBits]-bit hash (4 bits/char).
const int kAHashHexLen = kAHashBits ~/ 4; // 16

/// Lenient default Hamming distance under which two [averageHashFromGray]
/// fingerprints are treated as the same spot. 64-bit hashes of the same scene
/// typically differ by well under this; different scenes differ by ~32.
/// Deliberately generous: after repeated misses / a timeout the mission falls
/// back to slide-to-dismiss anyway, so erring lenient never traps — it only
/// spares the user needless retries. Tune on-device.
const int kPhotoMatchThreshold = 20;

/// A well-formed average-hash string: exactly [kAHashHexLen] hex chars.
bool isValidHash(String s) {
  if (s.length != kAHashHexLen) return false;
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    final isDigit = c >= 0x30 && c <= 0x39;
    final isLower = c >= 0x61 && c <= 0x66;
    final isUpper = c >= 0x41 && c <= 0x46;
    if (!isDigit && !isLower && !isUpper) return false;
  }
  return true;
}

/// Computes the average hash of [gray] — a row-major list of exactly
/// [kAHashBits] grayscale samples (0–255) — as a [kAHashHexLen]-char hex
/// string. Each bit is 1 where its pixel is `>=` the mean of all samples. Pure.
String averageHashFromGray(List<int> gray) {
  if (gray.length != kAHashBits) {
    throw ArgumentError('expected $kAHashBits samples, got ${gray.length}');
  }
  var sum = 0;
  for (final g in gray) {
    sum += g;
  }
  final mean = sum / kAHashBits;
  final bits = StringBuffer();
  for (final g in gray) {
    bits.write(g >= mean ? '1' : '0');
  }
  return _binToHex(bits.toString());
}

/// Decodes [bytes] (any format the `image` package understands — JPEG/PNG…),
/// downsizes to [kAHashSize]×[kAHashSize] grayscale and returns its
/// [averageHashFromGray]. Returns null when the bytes can't be decoded so the
/// caller degrades gracefully — an undecodable capture is treated as a missed
/// attempt, never a hard trap.
String? averageHashOfImageBytes(Uint8List bytes) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    // Some malformed inputs throw inside the decoder rather than returning
    // null — treat both the same: undecodable.
    return null;
  }
  if (decoded == null) return null;
  final small = img.copyResize(
    decoded,
    width: kAHashSize,
    height: kAHashSize,
    interpolation: img.Interpolation.average,
  );
  final gray = <int>[];
  for (var y = 0; y < kAHashSize; y++) {
    for (var x = 0; x < kAHashSize; x++) {
      final p = small.getPixel(x, y);
      // Rec. 601 luma; channels are 0–255 for a standard 8-bit decode.
      final lum = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round();
      gray.add(lum);
    }
  }
  return averageHashFromGray(gray);
}

/// Hamming distance (count of differing bits) between two equal-length hex
/// hashes. Throws if the lengths differ.
int hammingDistanceHex(String a, String b) {
  if (a.length != b.length) {
    throw ArgumentError('hash length mismatch: ${a.length} vs ${b.length}');
  }
  var dist = 0;
  for (var i = 0; i < a.length; i++) {
    var x = int.parse(a[i], radix: 16) ^ int.parse(b[i], radix: 16);
    while (x != 0) {
      dist += x & 1;
      x >>= 1;
    }
  }
  return dist;
}

/// Whether a ring-time [candidateHash] matches the alarm's registered
/// [referenceHash] closely enough to dismiss.
///
/// Anti-trap fallback: when [referenceHash] is null/blank/malformed — the alarm
/// was never configured with a reference photo, or its stored value isn't a
/// valid hash (e.g. a stray QR payload left in `missionData` from a different
/// mission) — ANY readable photo is accepted, exactly like the QR mission's
/// empty-code case. Otherwise the two fingerprints must be within [threshold]
/// bits. An unreadable candidate is a miss (false), which the widget counts
/// toward its retry/fallback budget rather than treating as a trap.
bool photoMatches(String? referenceHash, String candidateHash,
    {int threshold = kPhotoMatchThreshold}) {
  final ref = referenceHash?.trim() ?? '';
  if (!isValidHash(ref)) return true; // unconfigured / not a hash -> accept any
  final cand = candidateHash.trim();
  if (!isValidHash(cand)) return false; // unreadable capture -> a miss
  return hammingDistanceHex(ref, cand) <= threshold;
}

String _binToHex(String bits) {
  final sb = StringBuffer();
  for (var i = 0; i < bits.length; i += 4) {
    final nibble = bits.substring(i, i + 4);
    sb.write(int.parse(nibble, radix: 2).toRadixString(16));
  }
  return sb.toString();
}
