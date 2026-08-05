import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../components/rise_buttons.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Opens the QR registration scanner and resolves to the first scanned code, or
/// null if the user backed out without scanning. The captured value is what the
/// 'qr' dismiss mission will later require the user to scan.
Future<String?> registerQrCode(BuildContext context) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(builder: (_) => const QrRegisterScreen()),
  );
}

/// A full-screen one-shot scanner: the first readable code pops the route with
/// its value. Camera is a live platform view — device-verify only.
class QrRegisterScreen extends StatefulWidget {
  const QrRegisterScreen({super.key});

  @override
  State<QrRegisterScreen> createState() => _QrRegisterScreenState();
}

class _QrRegisterScreenState extends State<QrRegisterScreen> {
  late final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _captured = false;

  @override
  void initState() {
    super.initState();
    unawaited(_controller.start());
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_captured) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null || value.isEmpty) continue;
      _captured = true;
      Navigator.of(context).pop(value);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RiseColors.appBg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: RiseSpacing.screen, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GhostButton(
                      label: 'Cancel',
                      onPressed: () => Navigator.of(context).pop()),
                  Text('Register QR', style: RiseText.title),
                  const SizedBox(width: 64),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(RiseSpacing.screen),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Point the camera at the code you want to use to wake up. '
                      'Stick it somewhere out of bed.',
                      textAlign: TextAlign.center,
                      style: RiseText.body.copyWith(color: RiseColors.textDim),
                    ),
                    const SizedBox(height: 20),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(RiseRadii.lg),
                      child: SizedBox(
                        width: 260,
                        height: 260,
                        child: MobileScanner(
                          controller: _controller,
                          onDetect: _onDetect,
                          errorBuilder: (context, error) => Container(
                            color: RiseColors.surface2,
                            alignment: Alignment.center,
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              'Camera unavailable.\nGrant camera access to scan.',
                              textAlign: TextAlign.center,
                              style: RiseText.body
                                  .copyWith(color: RiseColors.textDim),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
