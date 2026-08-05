import 'dart:async';
import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../domain/eye_open.dart';
import '../components/rise_spinner.dart';
import '../components/slide_to_wake.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'mission_frame.dart';

/// An eye-open ("prove you're really up") dismiss mission: the front camera
/// streams to on-device ML Kit face detection, and the alarm dismisses once the
/// user has held BOTH eyes open (probability > [kEyeOpenThreshold]) for a
/// cumulative window ([eyeOpenWindowFor], scaled by difficulty). This defeats
/// the eyes-shut, half-asleep swipe-to-dismiss.
///
/// Anti-spoof: a live face must be classified each frame — a null probability
/// (no face / low confidence) contributes nothing. Holding up a static photo of
/// open eyes is a known limitation of on-device classification and is not
/// defended against here (it would need active liveness / blink challenges);
/// noted rather than over-engineered.
///
/// Anti-trap invariant: the mission can ALWAYS be completed. If the camera is
/// unavailable / permission denied, or no success within [fallbackAfter], it
/// degrades to a slide-to-wake escape that still dismisses.
///
/// The camera + ML Kit pipeline is a live platform integration that cannot run
/// in a headless widget test, so the widget is thin: the "have the eyes been
/// open long enough?" rule lives in the pure, unit-tested [sustainedOpen] /
/// [accumulateOpenMs]. Device-verify the preview, detection and timing.
class EyesMission extends StatefulWidget {
  const EyesMission({
    super.key,
    required this.diff,
    required this.onSolved,
    this.requiredOpen, // injectable required window for tests
    this.fallbackAfter = const Duration(seconds: 60),
    this.lensDirection = CameraLensDirection.front,
  });

  final String diff;
  final VoidCallback onSolved;
  final Duration? requiredOpen;
  final Duration fallbackAfter;
  final CameraLensDirection lensDirection;

  @override
  State<EyesMission> createState() => _EyesMissionState();
}

class _EyesMissionState extends State<EyesMission> {
  // A single frame's inter-arrival gap is capped so a stalled stream (or the
  // long first gap after init) can never dump seconds of "open" time at once —
  // wakefulness must be shown across real frames, not one lucky sample.
  static const int _maxFrameMs = 300;

  final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      performanceMode: FaceDetectorMode.fast,
    ),
  );

  late final Duration _required =
      widget.requiredOpen ?? eyeOpenWindowFor(widget.diff);

  CameraController? _controller;
  Timer? _fallbackTimer;
  bool _ready = false;
  bool _streaming = false;
  bool _busy = false;
  bool _solved = false;
  bool _fallback = false;
  int _openMs = 0;
  int? _lastFrameAtMs;

  @override
  void initState() {
    super.initState();
    _fallbackTimer = Timer(widget.fallbackAfter, _showFallback);
    unawaited(_init());
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    unawaited(_teardownCamera());
    unawaited(_detector.close());
    super.dispose();
  }

  Future<void> _teardownCamera() async {
    final controller = _controller;
    _controller = null;
    if (controller == null) return;
    try {
      if (_streaming) await controller.stopImageStream();
    } catch (_) {
      // best-effort
    }
    await controller.dispose();
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
      final controller = CameraController(
        desc,
        ResolutionPreset.low, // low res is plenty for eye-open classification
        enableAudio: false,
        imageFormatGroup:
            Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();
      if (!mounted) {
        unawaited(controller.dispose());
        return;
      }
      _controller = controller;
      await controller.startImageStream(_onFrame);
      _streaming = true;
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      // No camera / permission denied / init failure — never trap.
      _showFallback();
    }
  }

  void _showFallback() {
    if (_solved || _fallback || !mounted) return;
    setState(() => _fallback = true);
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_busy || _solved || _fallback) return;
    _busy = true;
    try {
      final input = _toInputImage(image);
      if (input == null) return;
      final faces = await _detector.processImage(input);
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final dt = _lastFrameAtMs == null
          ? 0
          : (nowMs - _lastFrameAtMs!).clamp(0, _maxFrameMs);
      _lastFrameAtMs = nowMs;

      final face = faces.isEmpty ? null : faces.first;
      final frame = (
        left: face?.leftEyeOpenProbability,
        right: face?.rightEyeOpenProbability,
        dtMs: dt,
      );
      if (bothEyesOpen(frame)) _openMs += dt;

      if (_openMs >= _required.inMilliseconds) {
        _solve();
      } else if (mounted) {
        setState(() {}); // refresh the progress meter
      }
    } catch (_) {
      // Drop a bad frame; the fallback timer still guarantees an escape.
    } finally {
      _busy = false;
    }
  }

  void _solve() {
    if (_solved) return;
    _solved = true;
    _fallbackTimer?.cancel();
    unawaited(_teardownCamera());
    widget.onSolved();
  }

  /// Converts a streamed [CameraImage] to an ML Kit [InputImage]. The camera is
  /// configured to deliver NV21 (Android) / BGRA8888 (iOS), each a single
  /// plane. Rotation uses the sensor orientation directly, which is correct for
  /// the portrait ring screen; full orientation compensation is a device-verify
  /// refinement. Returns null if the buffer looks unusable.
  InputImage? _toInputImage(CameraImage image) {
    final controller = _controller;
    if (controller == null || image.planes.isEmpty) return null;
    final rotation = InputImageRotationValue.fromRawValue(
            controller.description.sensorOrientation) ??
        InputImageRotation.rotation0deg;
    final format =
        Platform.isAndroid ? InputImageFormat.nv21 : InputImageFormat.bgra8888;
    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  /// Fits the live preview into its fixed-size box without distorting it.
  /// `CameraPreview` wraps its texture in its own `AspectRatio`, but that
  /// widget silently collapses to whatever tight box it's handed (see
  /// Flutter's `RenderAspectRatio._applyAspectRatio`) instead of honouring
  /// the camera's real ratio — so naively placing it in a fixed 220x220 box
  /// stretches the feed to fill a square. Giving it its own natural size
  /// inside a `FittedBox` lets it size correctly, then scales/crops that
  /// correctly-proportioned preview to fill the visible box, matching how
  /// the QR mission's scanner (which does this internally) already looks.
  Widget _cameraPreview(CameraController controller) {
    final previewSize = controller.value.previewSize;
    if (previewSize == null) return CameraPreview(controller);
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        // previewSize is reported in the camera sensor's own (landscape)
        // orientation regardless of device orientation, so on a portrait
        // phone its width/height are swapped relative to what's on screen.
        width: previewSize.height,
        height: previewSize.width,
        child: CameraPreview(controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_fallback) {
      return MissionFrame(
        instruction: "Can't check your eyes right now",
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

    final controller = _controller;
    final total = _required.inMilliseconds;
    final progress = total == 0 ? 1.0 : (_openMs / total).clamp(0.0, 1.0);
    return MissionFrame(
      instruction: 'Keep both eyes open',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(RiseRadii.lg),
            child: SizedBox(
              width: 220,
              height: 220,
              child: _ready && controller != null
                  ? _cameraPreview(controller)
                  : Container(
                      color: RiseColors.surface2,
                      alignment: Alignment.center,
                      child: const RiseSpinner(size: 28),
                    ),
            ),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(RiseRadii.pill),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: RiseColors.surface2,
              valueColor: AlwaysStoppedAnimation<Color>(RiseColors.primary),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _ready ? 'Hold steady…' : 'Point the front camera at your face',
            textAlign: TextAlign.center,
            style: RiseText.caption.copyWith(color: RiseColors.textDim),
          ),
        ],
      ),
    );
  }
}
