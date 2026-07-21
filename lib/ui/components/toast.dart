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
        return const Icon(Icons.check_circle_rounded,
            size: 16, color: RiseColors.positive);
      case RiseToastKind.error:
        return const Icon(Icons.error_rounded, size: 16, color: RiseColors.danger);
      case RiseToastKind.info:
        return Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
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
  });

  final String? message;
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
            child: Center(child: RiseToast(widget.message!)),
          ),
      ],
    );
  }
}
