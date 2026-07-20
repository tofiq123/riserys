import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'mission_frame.dart';

/// Whether a scanned QR/barcode [scanned] value dismisses the alarm given the
/// alarm's registered [expected] payload.
///
/// Anti-trap fallback: when [expected] is null or empty (the alarm was never
/// configured with a specific code) ANY scan is accepted, so an unconfigured
/// QR alarm can never trap the user. Otherwise the values must match (both
/// trimmed, to tolerate stray whitespace from the decoder).
bool qrMatches(String? expected, String scanned) {
  final want = expected?.trim() ?? '';
  if (want.isEmpty) return true;
  return scanned.trim() == want;
}

/// A "scan a code" dismiss mission: the user points the camera at the QR code
/// (or any barcode) they registered for this alarm — typically stuck somewhere
/// out of bed, like the bathroom mirror — and scanning the right code dismisses.
///
/// The camera preview is a live platform view and cannot be exercised in a
/// headless widget test, so the widget is kept thin and the dismiss decision is
/// factored into the pure [qrMatches] (unit-tested). Device-verify the camera.
class QrMission extends StatefulWidget {
  const QrMission({
    super.key,
    required this.onSolved,
    this.expected, // the registered code; null/empty => accept any scan
  });

  final VoidCallback onSolved;
  final String? expected;

  @override
  State<QrMission> createState() => _QrMissionState();
}

class _QrMissionState extends State<QrMission> {
  late final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _solved = false;
  bool _wrong = false;

  @override
  void initState() {
    super.initState();
    // When a controller is supplied to MobileScanner it does not auto-start;
    // start it here and dispose it below.
    unawaited(_controller.start());
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_solved) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null) continue;
      if (qrMatches(widget.expected, value)) {
        _solved = true;
        widget.onSolved();
        return;
      }
      // A readable but wrong code: hint without trapping — keep scanning.
      if (!_wrong && mounted) setState(() => _wrong = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final anyCode = (widget.expected?.trim() ?? '').isEmpty;
    return MissionFrame(
      instruction:
          anyCode ? 'Scan any code to dismiss' : 'Scan your code to dismiss',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(RiseRadii.lg),
            child: SizedBox(
              width: 240,
              height: 240,
              child: MobileScanner(
                controller: _controller,
                onDetect: _onDetect,
                errorBuilder: (context, error, child) => Container(
                  color: RiseColors.surface2,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Camera unavailable.\nGrant camera access to scan.',
                    textAlign: TextAlign.center,
                    style: RiseText.body.copyWith(color: RiseColors.textDim),
                  ),
                ),
              ),
            ),
          ),
          if (_wrong) ...[
            const SizedBox(height: 12),
            Text('Not the right code — try the one you registered',
                textAlign: TextAlign.center,
                style: RiseText.caption.copyWith(color: RiseColors.danger)),
          ],
        ],
      ),
    );
  }
}
