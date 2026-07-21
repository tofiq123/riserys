import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The shared crew bottom-sheet chrome: card surface, top-rounded corners, a
/// grab handle, and keyboard-aware bottom padding. Every crew sheet (add
/// people, requests, the friend overflow) opens through this so they feel like
/// one system.
Future<T?> showCrewSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: RiseColors.card,
    barrierColor: const Color(0x66000000),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(RiseRadii.lg)),
    ),
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: RiseColors.border,
                borderRadius: BorderRadius.circular(RiseRadii.pill),
              ),
            ),
            builder(sheetContext),
          ],
        ),
      ),
    ),
  );
}
