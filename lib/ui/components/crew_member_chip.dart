import 'package:flutter/widgets.dart';

import '../../domain/crew_member.dart';
import '../../domain/crew_status.dart';
import '../theme/typography.dart';
import 'crew_avatar.dart';
import 'crew_status_style.dart';

/// One member on the This-morning strip: their avatar wrapped in a status
/// ring, their first name, and the tiny status word — the at-a-glance "how is
/// everyone's morning going" unit. Tapping opens their detail page.
class CrewMemberChip extends StatelessWidget {
  const CrewMemberChip({
    super.key,
    required this.member,
    required this.status,
    required this.onTap,
  });

  final CrewMember member;
  final CrewStatus status;
  final VoidCallback onTap;

  String get _name {
    if (member.displayName.isNotEmpty) {
      return member.displayName.split(' ').first;
    }
    return '@${member.username}';
  }

  @override
  Widget build(BuildContext context) {
    final style = crewStatusStyle(status);
    return GestureDetector(
      key: Key('crew-chip-${member.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 78,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CrewAvatar(
              username: member.username,
              colorHex: member.avatarColor,
              size: 52,
              ring: status,
            ),
            const SizedBox(height: 7),
            Text(
              _name,
              style: RiseText.body.copyWith(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 1),
            Text(
              style.word,
              style: RiseText.caption.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: style.color,
              ),
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }
}

/// Orders members for the This-morning strip: waking first (cheer them on!),
/// then awake, asleep, and quiet last; name as a stable tiebreak. Pure —
/// returns a new list.
List<CrewMember> sortMembersByStatus(
  List<CrewMember> members,
  Map<String, CrewStatus> statuses,
) {
  final list = [...members];
  list.sort((a, b) {
    final ra = crewStatusStyle(statuses[a.id] ?? CrewStatus.unknown).rank;
    final rb = crewStatusStyle(statuses[b.id] ?? CrewStatus.unknown).rank;
    if (ra != rb) return ra.compareTo(rb);
    return a.username.compareTo(b.username);
  });
  return list;
}
