import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

/// The app's one "couldn't load" state. Several `.when(error:)` branches used to
/// fall through to the empty state, so a network failure looked identical to
/// "you have nothing yet" and offered no way to recover. Use this instead: a
/// quiet line plus a Retry that re-runs the failed load (typically
/// `ref.invalidate(theProvider)`).
class RiseErrorCard extends StatelessWidget {
  const RiseErrorCard({
    super.key,
    required this.message,
    this.onRetry,
    this.padding = const EdgeInsets.symmetric(vertical: 18),
  });

  /// A short, plain description, e.g. 'Couldn't load your crew.'
  final String message;

  /// Re-runs the load. When null, no Retry action is shown.
  final VoidCallback? onRetry;

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: padding,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined,
                  size: 18, color: RiseColors.textFaint),
              const SizedBox(width: 10),
              Flexible(child: Text(message, style: RiseText.caption)),
              if (onRetry != null) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onRetry,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                    child: Text('Retry',
                        style: RiseText.caption.copyWith(
                            color: RiseColors.text,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
}
