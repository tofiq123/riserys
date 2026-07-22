import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../domain/photo_match.dart';
import '../components/rise_spinner.dart';
import '../components/slide_to_wake.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'mission_frame.dart';

/// A "snap a spot" dismiss mission: the user registered a reference photo of a
/// spot away from bed (a kettle, the bathroom mirror, a poster). At ring time
/// they must photograph the same spot; a lenient perceptual-hash match
/// ([photoMatches]) dismisses the alarm.
///
/// Anti-trap invariant. The mission can ALWAYS be completed:
///  * an unconfigured alarm ([reference] null/empty/malformed) accepts any
///    readable photo (see [photoMatches]);
///  * after [maxAttempts] mismatches, or if the camera is unavailable / denied,
///    or after [fallbackAfter] with no success, it degrades to a slide-to-wake
///    escape that still dismisses.
///
/// The live camera preview is a platform view that cannot render in a headless
/// widget test, so the widget is kept thin: all of the pass/fail logic lives in
/// the pure, unit-tested [photoMatches] / hashing functions. Device-verify the
/// preview, capture and on-device hashing.
class PhotoMission extends StatefulWidget {
  const PhotoMission({
    super.key,
    required this.onSolved,
    this.reference, // registered aHash; null/empty/invalid => accept any photo
    this.fallbackAfter = const Duration(seconds: 60),
    this.maxAttempts = 3,
    this.lensDirection = CameraLensDirection.back,
  });

  final VoidCallback onSolved;
  final String? reference;
  final Duration fallbackAfter;
  final int maxAttempts;
  final CameraLensDirection lensDirection;

  @override
  State<PhotoMission> createState() => _PhotoMissionState();
}

class _PhotoMissionState extends State<PhotoMission> {
  CameraController? _controller;
  Timer? _fallbackTimer;
  bool _ready = false;
  bool _busy = false;
  bool _solved = false;
  bool _fallback = false;
  bool _wrong = false;
  int _attempts = 0;

  @override
  void initState() {
    super.initState();
    _fallbackTimer = Timer(widget.fallbackAfter, _showFallback);
    unawaited(_init());
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    unawaited(_controller?.dispose());
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        _showFallback();
        return;
      }
      final desc = cams.firstWhere(
        (c) => c.lensDirection == widget.lensDirection,
        orElse: () => cams.first,
      );
      // Medium keeps captures small so the on-device hash stays fast.
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
      // No camera / permission denied / init failure — never trap.
      _showFallback();
    }
  }

  void _showFallback() {
    if (_solved || _fallback || !mounted) return;
    setState(() => _fallback = true);
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (_busy || _solved || controller == null) return;
    setState(() {
      _busy = true;
      _wrong = false;
    });
    try {
      final shot = await controller.takePicture();
      final bytes = await shot.readAsBytes();
      final hash = averageHashOfImageBytes(bytes) ?? '';
      if (photoMatches(widget.reference, hash)) {
        _solved = true;
        _fallbackTimer?.cancel();
        widget.onSolved();
        return;
      }
      _registerMiss();
    } catch (_) {
      // A capture/decoding failure counts as a miss so a broken camera still
      // reaches the fallback rather than looping forever.
      _registerMiss();
    } finally {
      if (mounted && !_solved) setState(() => _busy = false);
    }
  }

  void _registerMiss() {
    _attempts++;
    if (_attempts >= widget.maxAttempts) {
      _showFallback();
    } else if (mounted) {
      setState(() => _wrong = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_fallback) {
      return MissionFrame(
        instruction: "Can't check the photo right now",
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Slide to wake up instead',
                textAlign: TextAlign.center,
                style: RiseText.caption.copyWith(color: RiseColors.textDim)),
            const SizedBox(height: 14),
            SlideToWake(onWake: widget.onSolved),
          ],
        ),
      );
    }

    final anyPhoto = !isValidHash((widget.reference?.trim() ?? ''));
    final controller = _controller;
    return MissionFrame(
      instruction:
          anyPhoto ? 'Take a photo to dismiss' : 'Snap your registered spot',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(RiseRadii.lg),
            child: SizedBox(
              width: 240,
              height: 240,
              child: _ready && controller != null
                  ? CameraPreview(controller)
                  : Container(
                      color: RiseColors.surface2,
                      alignment: Alignment.center,
                      child: const RiseSpinner(size: 28),
                    ),
            ),
          ),
          if (_wrong) ...[
            const SizedBox(height: 12),
            Text(
              'That spot doesn\'t look right — try again '
              '(${widget.maxAttempts - _attempts} left)',
              textAlign: TextAlign.center,
              style: RiseText.caption.copyWith(color: RiseColors.danger),
            ),
          ],
          const SizedBox(height: 16),
          _ShutterButton(
            enabled: _ready && !_busy,
            onPressed: _capture,
          ),
        ],
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onPressed : null,
      child: Container(
        width: 150,
        height: 56,
        decoration: BoxDecoration(
          color: enabled ? RiseColors.primary : RiseColors.surface2,
          borderRadius: BorderRadius.circular(RiseRadii.lg),
          boxShadow: enabled ? RiseShadows.primary : null,
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo_camera,
                size: 22,
                color:
                    enabled ? RiseColors.primaryText : RiseColors.textDim),
            const SizedBox(width: 8),
            Text('Take photo',
                style: RiseText.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: enabled
                        ? RiseColors.primaryText
                        : RiseColors.textDim)),
          ],
        ),
      ),
    );
  }
}
