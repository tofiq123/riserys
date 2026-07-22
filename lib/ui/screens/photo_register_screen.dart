import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../domain/photo_match.dart';
import '../components/rise_buttons.dart';
import '../components/rise_spinner.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Opens the reference-photo capture screen and resolves to the perceptual
/// (average) hash of the captured spot, or null if the user backed out without
/// capturing. The hash string is what the 'photo' dismiss mission later
/// matches against — see [averageHashOfImageBytes] / [photoMatches].
Future<String?> registerReferencePhoto(BuildContext context) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(builder: (_) => const PhotoRegisterScreen()),
  );
}

/// A full-screen one-shot camera: the first successful capture pops the route
/// with the photo's average hash. Camera is a live platform view —
/// device-verify only.
class PhotoRegisterScreen extends StatefulWidget {
  const PhotoRegisterScreen({super.key});

  @override
  State<PhotoRegisterScreen> createState() => _PhotoRegisterScreenState();
}

class _PhotoRegisterScreenState extends State<PhotoRegisterScreen> {
  CameraController? _controller;
  bool _ready = false;
  bool _busy = false;
  bool _error = false;
  bool _captured = false;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  @override
  void dispose() {
    unawaited(_controller?.dispose());
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        if (mounted) setState(() => _error = true);
        return;
      }
      final desc = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      final controller = CameraController(
        desc,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        unawaited(controller.dispose());
        return;
      }
      setState(() {
        _controller = controller;
        _ready = true;
      });
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (_busy || _captured || controller == null) return;
    setState(() => _busy = true);
    try {
      final shot = await controller.takePicture();
      final bytes = await shot.readAsBytes();
      final hash = averageHashOfImageBytes(bytes);
      if (hash == null) {
        if (mounted) setState(() => _busy = false);
        return; // couldn't decode — let the user try again
      }
      _captured = true;
      if (mounted) Navigator.of(context).pop(hash);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
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
                  Text('Register photo', style: RiseText.title),
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
                      'Point the camera at a spot away from bed — a kettle, a '
                      'poster, the bathroom mirror — and capture it. You\'ll '
                      'snap the same spot to turn the alarm off.',
                      textAlign: TextAlign.center,
                      style: RiseText.body.copyWith(color: RiseColors.textDim),
                    ),
                    const SizedBox(height: 20),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(RiseRadii.lg),
                      child: SizedBox(
                        width: 260,
                        height: 260,
                        child: _buildViewfinder(),
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (!_error)
                      PrimaryButton(
                        label: 'Capture spot',
                        onPressed: (_ready && !_busy) ? _capture : null,
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

  Widget _buildViewfinder() {
    if (_error) {
      return Container(
        color: RiseColors.surface2,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(16),
        child: Text(
          'Camera unavailable.\nGrant camera access to register a photo.',
          textAlign: TextAlign.center,
          style: RiseText.body.copyWith(color: RiseColors.textDim),
        ),
      );
    }
    final controller = _controller;
    if (_ready && controller != null) {
      return CameraPreview(controller);
    }
    return Container(
      color: RiseColors.surface2,
      alignment: Alignment.center,
      child: const RiseSpinner(size: 28),
    );
  }
}
