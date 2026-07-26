import 'package:flutter/widgets.dart';

/// The app's touch feedback: a quick, subtle press-scale on every tappable
/// surface, so the whole UI answers the finger the same way. Wrap the visual
/// (usually a card or row) and pass the tap handlers here instead of an outer
/// GestureDetector. Renders statically under reduced motion.
class RisePressable extends StatefulWidget {
  const RisePressable({
    super.key,
    required this.onTap,
    this.onLongPress,
    required this.child,
    this.enabled = true,
  });

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget child;

  /// When false the press animation is skipped (e.g. a busy row) but taps
  /// still dispatch to [onTap] (usually null while busy).
  final bool enabled;

  @override
  State<RisePressable> createState() => _RisePressableState();
}

class _RisePressableState extends State<RisePressable> {
  bool _down = false;

  bool get _animates =>
      widget.enabled &&
      widget.onTap != null &&
      !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);

  void _set(bool down) {
    if (_down == down || !_animates) return;
    setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      child: AnimatedScale(
        scale: _down ? 0.975 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// A headline numeral that counts up on first paint — the app's one micro
/// moment, used for the streak and the live up-count.
///
/// Only animates when the target value itself changes, never on an unrelated
/// rebuild (a reaction tap must not re-run the streak's count-up), and renders
/// statically under reduced motion.
class RiseCountUp extends StatelessWidget {
  const RiseCountUp({super.key, required this.value, required this.style});

  final int value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce || value == 0) return Text('$value', style: style);
    return TweenAnimationBuilder<double>(
      key: ValueKey(value),
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      builder: (_, v, __) => Text('${v.round()}', style: style),
    );
  }
}

/// The app's state transition: when a section swaps between loading skeleton,
/// content, and error, the change melts (fade + a whisper of scale) instead of
/// popping. Give each branch a distinct [ValueKey] via [keyed]. Instant under
/// reduced motion.
class RiseFade extends StatelessWidget {
  const RiseFade({super.key, required this.child});

  final Widget child;

  /// Convenience: tag a branch so the switcher sees it as a distinct state.
  static Widget keyed(String state, Widget child) =>
      KeyedSubtree(key: ValueKey(state), child: child);

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) return child;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.985, end: 1.0).animate(animation),
          child: child,
        ),
      ),
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, if (current != null) current],
      ),
      child: child,
    );
  }
}
