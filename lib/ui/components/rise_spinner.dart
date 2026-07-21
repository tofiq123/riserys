import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The app's one loading spinner. A bare [CircularProgressIndicator] inherits
/// the Material default colour (purple in the app's light theme, which ships
/// `theme: null`) — off-brand for the monochrome Mono system. Always use this so
/// every loader is the brand near-black/near-white, at a consistent size.
///
/// Default colour is [RiseColors.primary]; pass [color] for on-primary contexts
/// (e.g. a spinner inside a filled button, where [RiseColors.primaryText] reads
/// correctly).
class RiseSpinner extends StatelessWidget {
  const RiseSpinner({
    super.key,
    this.size = 22,
    this.strokeWidth = 2,
    this.color,
  });

  final double size;
  final double strokeWidth;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(
          strokeWidth: strokeWidth,
          color: color ?? RiseColors.primary,
        ),
      );
}
