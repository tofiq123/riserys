import 'dart:async';

import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

/// The dark pill toast visual.
class RiseToast extends StatelessWidget {
  const RiseToast(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
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
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(color: RiseColors.primaryText, shape: BoxShape.circle),
          ),
          const SizedBox(width: 9),
          Text(message,
              style: RiseText.body.copyWith(
                  fontSize: 13.5, fontWeight: FontWeight.w600, color: RiseColors.primaryText)),
        ],
      ),
    );
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
