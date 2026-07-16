import 'package:flutter/material.dart';

import '../../data/permission_gateway.dart';
import '../components/permissions_section.dart';
import '../components/rise_card.dart';
import '../components/section_label.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen(
      {super.key, this.permissions = const NativePermissionGateway()});

  final PermissionGateway permissions;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            RiseSpacing.screen, 8, RiseSpacing.screen, 40),
        children: [
          Text('Profile', style: RiseText.display),
          const SizedBox(height: 16),
          RiseCard(
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(
                      color: RiseColors.accentSoft, shape: BoxShape.circle),
                  child: const Icon(Icons.person_outline,
                      color: RiseColors.accent, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Guest',
                          style: RiseText.body
                              .copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text('Sign in to sync your alarms and crew — coming soon',
                          style: RiseText.caption),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const SectionLabel('Reliability'),
          const SizedBox(height: 6),
          Text('Make sure Rise can always reach you.', style: RiseText.caption),
          const SizedBox(height: 12),
          PermissionsSection(gateway: permissions),
          const SizedBox(height: 24),
          const SectionLabel('About'),
          const SizedBox(height: 12),
          RiseCard(
            child: Column(
              children: [
                _aboutRow('Version', '1.0.0'),
                const Divider(height: 20, color: RiseColors.divider),
                _aboutRow('Made for', 'waking up, 100%'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _aboutRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: RiseText.body.copyWith(color: RiseColors.textDim)),
        Text(value, style: RiseText.body.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}
