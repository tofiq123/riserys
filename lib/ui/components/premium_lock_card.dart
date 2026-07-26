import 'package:flutter/material.dart';

import '../screens/paywall_screen.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'rise_card.dart';
import 'rise_motion.dart';

/// A "this is premium" card that routes to the paywall.
///
/// Used where a premium section would otherwise render, so the value stays
/// visible and the lock sits on the control — never a blank slot the user has
/// to guess about.
Widget premiumLockCard(BuildContext context, String label) => RisePressable(
      onTap: () => openPaywall(context),
      child: RiseCard(
        child: Row(
          children: [
            Icon(Icons.lock_outline, size: 20, color: RiseColors.textDim),
            const SizedBox(width: 12),
            Expanded(
                child: Text(label,
                    style: RiseText.body.copyWith(fontWeight: FontWeight.w600))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: RiseColors.primary,
                borderRadius: BorderRadius.circular(RiseRadii.pill),
              ),
              child: Text('PREMIUM',
                  style: RiseText.sectionLabel
                      .copyWith(fontSize: 9, color: RiseColors.primaryText)),
            ),
          ],
        ),
      ),
    );
