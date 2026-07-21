import 'package:flutter/widgets.dart';

/// First-build entrance for the crew surfaces: a soft fade + a small rise,
/// staggered by [index] so sections settle top-to-bottom. Runs once per mount,
/// never on rebuilds, and renders statically when the platform asks for
/// reduced motion ([MediaQueryData.disableAnimations]).
class CrewEntrance extends StatefulWidget {
  const CrewEntrance({super.key, this.index = 0, required this.child});

  /// Position in the stagger (0 = first). Capped so late sections never lag.
  final int index;

  final Widget child;

  @override
  State<CrewEntrance> createState() => _CrewEntranceState();
}

class _CrewEntranceState extends State<CrewEntrance>
    with SingleTickerProviderStateMixin {
  static const _step = Duration(milliseconds: 55);
  static const _rise = Duration(milliseconds: 320);
  static const _maxStagger = 6;

  AnimationController? _controller;
  Animation<double>? _fade;
  Animation<Offset>? _slide;
  bool _decided = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) return;
    _decided = true;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) return; // No controller: the child renders in place.
    final delay = _step * widget.index.clamp(0, _maxStagger);
    final total = _rise + delay;
    final controller = AnimationController(vsync: this, duration: total);
    final curve = CurvedAnimation(
      parent: controller,
      curve: Interval(
        delay.inMilliseconds / total.inMilliseconds,
        1,
        curve: Curves.easeOutCubic,
      ),
    );
    _controller = controller;
    _fade = curve;
    _slide = Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero)
        .animate(curve);
    controller.forward();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fade = _fade;
    final slide = _slide;
    if (fade == null || slide == null) return widget.child;
    return FadeTransition(
      opacity: fade,
      child: SlideTransition(position: slide, child: widget.child),
    );
  }
}
