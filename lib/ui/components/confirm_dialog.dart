import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'rise_buttons.dart';

/// A branded Cancel / Confirm modal in the Mono style. Resolves to `true` only
/// when the user taps the confirm action; a dismiss or Cancel resolves `false`.
/// Use before any destructive or hard-to-undo action.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool danger = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: RiseColors.card,
      title: Text(title, style: RiseText.title),
      content: Text(message,
          style: RiseText.body.copyWith(color: RiseColors.textDim)),
      actions: [
        GhostButton(
          label: cancelLabel,
          onPressed: () => Navigator.of(dialogContext).pop(false),
        ),
        GestureDetector(
          key: const Key('confirm-dialog-confirm'),
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(dialogContext).pop(true),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Text(confirmLabel,
                style: RiseText.body.copyWith(
                  color: danger ? RiseColors.danger : RiseColors.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                )),
          ),
        ),
      ],
    ),
  );
  return result ?? false;
}
