import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

/// The tone of a [RiseToast]: a neutral notice, a completed action, or a
/// failure. Drives the leading icon and its accent — the dark pill is shared.
enum RiseToastKind { success, error, info }

/// The dark pill toast visual. [kind] picks the small leading indicator: a
/// green check for [RiseToastKind.success], a red alert for
/// [RiseToastKind.error], and the neutral dot for [RiseToastKind.info]
/// (the default — the original look, so single-arg call sites are unchanged).
class RiseToast extends StatelessWidget {
  const RiseToast(this.message, {super.key, this.kind = RiseToastKind.info});

  final String message;
  final RiseToastKind kind;

  /// Shows [message] as a branded toast over the top-most overlay, so it works
  /// from anywhere — shell tabs, dialogs and pushed routes alike. It fades in
  /// near the bottom, auto-dismisses after ~2.7s, and is tap-to-dismiss.
  ///
  /// Never throws and never blocks: if no overlay is reachable it is a graceful
  /// no-op, and it honours [MediaQueryData.disableAnimations].
  static void show(
    BuildContext context,
    String message, {
    RiseToastKind kind = RiseToastKind.info,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _OverlayToast(
        message: message,
        kind: kind,
        reduceMotion: reduceMotion,
        onDismiss: () {
          if (entry.mounted) entry.remove();
        },
      ),
    );
    overlay.insert(entry);
  }

  @override
  Widget build(BuildContext context) {
    // Cap the width so a long message wraps into the pill instead of
    // overflowing on a narrow phone; short messages stay compact and centered.
    final width = MediaQuery.maybeOf(context)?.size.width ?? 420;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: (width - 48).clamp(160.0, 440.0)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 11),
        decoration: BoxDecoration(
          color: RiseColors.primary,
          borderRadius: BorderRadius.circular(RiseRadii.pill),
          boxShadow: const [
            BoxShadow(color: Color(0x47000000), offset: Offset(0, 8), blurRadius: 30),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _leading(),
            const SizedBox(width: 9),
            Flexible(
              child: Text(message,
                  style: RiseText.body.copyWith(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: RiseColors.primaryText)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _leading() {
    switch (kind) {
      case RiseToastKind.success:
        return Icon(Icons.check_circle_rounded,
            size: 16, color: RiseColors.positive);
      case RiseToastKind.error:
        return Icon(Icons.error_rounded, size: 16, color: RiseColors.danger);
      case RiseToastKind.info:
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
              color: RiseColors.primaryText, shape: BoxShape.circle),
        );
    }
  }
}

/// Overlays [message] near the bottom of [child] and calls [onHide] ~2.7s after
/// it appears. The parent clears its message state in [onHide].
class ToastHost extends StatefulWidget {
  const ToastHost({
    super.key,
    required this.message,
    required this.onHide,
    required this.child,
    this.kind = RiseToastKind.info,
  });

  final String? message;
  final RiseToastKind kind;
  final VoidCallback onHide;
  final Widget child;

  @override
  State<ToastHost> createState() => _ToastHostState();
}

class _ToastHostState extends State<ToastHost> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.message != null) _arm();
  }

  @override
  void didUpdateWidget(ToastHost old) {
    super.didUpdateWidget(old);
    if (widget.message != null && widget.message != old.message) _arm();
  }

  void _arm() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 2700), () {
      if (mounted) widget.onHide();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (widget.message != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 104,
            child: Center(child: RiseToast(widget.message!, kind: widget.kind)),
          ),
      ],
    );
  }
}

/// The overlay-hosted toast used by [RiseToast.show]: fades/slides in, holds for
/// ~2.7s, then removes itself. Tapping it dismisses early. Only the pill absorbs
/// pointers, so the rest of the screen stays interactive underneath.
class _OverlayToast extends StatefulWidget {
  const _OverlayToast({
    required this.message,
    required this.kind,
    required this.reduceMotion,
    required this.onDismiss,
  });

  final String message;
  final RiseToastKind kind;
  final bool reduceMotion;
  final VoidCallback onDismiss;

  @override
  State<_OverlayToast> createState() => _OverlayToastState();
}

class _OverlayToastState extends State<_OverlayToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    reverseDuration: const Duration(milliseconds: 180),
  );
  late final Animation<double> _fade =
      CurvedAnimation(parent: _c, curve: Curves.easeOut, reverseCurve: Curves.easeIn);
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.22),
    end: Offset.zero,
  ).animate(CurvedAnimation(
      parent: _c, curve: Curves.easeOutCubic, reverseCurve: Curves.easeIn));

  Timer? _timer;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    if (widget.reduceMotion) {
      _c.value = 1.0;
    } else {
      _c.forward();
    }
    _timer = Timer(const Duration(milliseconds: 2700), _dismiss);
  }

  void _dismiss() {
    if (_dismissing) return;
    _dismissing = true;
    _timer?.cancel();
    if (widget.reduceMotion) {
      widget.onDismiss();
      return;
    }
    _c.reverse().whenComplete(widget.onDismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 40),
          child: Center(
            heightFactor: 1,
            child: FadeTransition(
              opacity: _fade,
              child: SlideTransition(
                position: _slide,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _dismiss,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: RiseToast(widget.message, kind: widget.kind),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
