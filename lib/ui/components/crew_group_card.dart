import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/crew_member.dart';
import '../../domain/group.dart';
import '../state/group_providers.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'crew_avatar.dart';
import 'rise_motion.dart';

/// Card metrics shared by the Groups strip so real and dashed cards align.
const double kCrewGroupCardWidth = 156;
const double kCrewGroupCardHeight = 116;

/// One group on the dashboard strip: stacked member avatars (roster read
/// lazily via the existing [groupMembersProvider]), the group name, and a
/// member count. Tapping opens the group's page.
class CrewGroupCard extends ConsumerWidget {
  const CrewGroupCard({super.key, required this.group, required this.onTap});

  final Group group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(groupMembersProvider(group.id)).value;
    final count = members?.length ?? group.memberCount;
    return RisePressable(
      key: Key('group-card-${group.id}'),
      onTap: onTap,
      child: Container(
        width: kCrewGroupCardWidth,
        height: kCrewGroupCardHeight,
        padding: const EdgeInsets.all(RiseSpacing.cardPad),
        decoration: BoxDecoration(
          color: RiseColors.card,
          borderRadius: BorderRadius.circular(RiseRadii.base),
          border: Border.all(color: RiseColors.border),
          boxShadow: RiseShadows.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _avatarStack(members),
            const Spacer(),
            Text(group.name,
                style: RiseText.body.copyWith(
                    fontWeight: FontWeight.w600, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(
              count == null
                  ? (group.isOwner ? 'Your group' : 'Member')
                  : '$count ${count == 1 ? 'member' : 'members'}',
              style: RiseText.caption.copyWith(fontSize: 11.5),
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }

  /// Up to three overlapping member avatars, with a "+N" spill chip. Before
  /// the roster loads, a quiet group glyph holds the space.
  Widget _avatarStack(List<CrewMember>? members) {
    if (members == null || members.isEmpty) {
      return Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: RiseColors.accentSoft,
          shape: BoxShape.circle,
          border: Border.all(color: RiseColors.border),
        ),
        child: Icon(Icons.groups_outlined, size: 16, color: RiseColors.textDim),
      );
    }
    final shown = members.take(3).toList();
    final extra = members.length - shown.length;
    final slots = shown.length + (extra > 0 ? 1 : 0);
    return SizedBox(
      height: 30,
      width: 30.0 + (slots - 1) * 20.0,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * 20.0,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: RiseColors.card, width: 2),
                ),
                child: CrewAvatar(
                  username: shown[i].username,
                  colorHex: shown[i].avatarColor,
                  size: 26,
                ),
              ),
            ),
          if (extra > 0)
            Positioned(
              left: shown.length * 20.0,
              child: Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: RiseColors.surface2,
                  shape: BoxShape.circle,
                  border: Border.all(color: RiseColors.border),
                ),
                child: Text('+$extra',
                    style: RiseText.mono(size: 10, weight: FontWeight.w600)),
              ),
            ),
        ],
      ),
    );
  }
}

/// A dashed "action" card on the Groups strip ("New group", "Join a group"):
/// same footprint as a group card, quiet dashed border, icon + label.
class CrewDashedCard extends StatelessWidget {
  const CrewDashedCard({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return RisePressable(
      onTap: onTap,
      child: CustomPaint(
        foregroundPainter: _DashedBorderPainter(
          color: RiseColors.border,
          radius: RiseRadii.base,
        ),
        child: Container(
          width: kCrewGroupCardWidth,
          height: kCrewGroupCardHeight,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: RiseColors.surface2,
            borderRadius: BorderRadius.circular(RiseRadii.base),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: RiseColors.textDim),
              const SizedBox(height: 8),
              Text(label,
                  style: RiseText.body.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: RiseColors.textDim)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Draws a 1px dashed rounded-rect border (Flutter has no dashed BorderStyle).
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect.deflate(0.6));
    const dash = 5.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}
