import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// A quiet loading placeholder in the Mono language: a `surface2` block with a
/// slow opacity pulse. Used wherever content is *expected* to appear (skeleton
/// mirrors the final layout, so nothing jumps), in place of an attention-
/// grabbing spinner. Spinners remain only for in-button busy states.
///
/// Under reduced motion the pulse is disabled and the block renders statically.
class RiseSkeleton extends StatefulWidget {
  const RiseSkeleton({
    super.key,
    this.width,
    required this.height,
    this.radius = RiseRadii.sm,
  });

  /// Fixed width, or null to fill the parent's width constraint.
  final double? width;
  final double height;
  final double radius;

  @override
  State<RiseSkeleton> createState() => _RiseSkeletonState();
}

class _RiseSkeletonState extends State<RiseSkeleton>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  bool _decided = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) return;
    _decided = true;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) return; // Static block; no ticker at all.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final block = Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: RiseColors.surface2,
        borderRadius: BorderRadius.circular(widget.radius),
        border: Border.all(color: RiseColors.border),
      ),
    );
    final controller = _controller;
    if (controller == null) {
      return Opacity(opacity: 0.75, child: block);
    }
    return FadeTransition(
      opacity: Tween<double>(begin: 0.55, end: 1.0).animate(
          CurvedAnimation(parent: controller, curve: Curves.easeInOut)),
      child: block,
    );
  }
}

/// Circular [RiseSkeleton] counterpart for avatar placeholders.
class RiseSkeletonCircle extends StatelessWidget {
  const RiseSkeletonCircle({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) =>
      RiseSkeleton(width: size, height: size, radius: size / 2);
}
