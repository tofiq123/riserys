import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/crew/crew_service.dart';
import '../../domain/crew_member.dart';
import '../../domain/crew_state.dart';
import '../state/crew_providers.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'crew_avatar.dart';
import 'crew_pill.dart';
import 'crew_sheet.dart';
import 'toast.dart';

/// Opens the incoming-requests sheet: one row per person asking to join your
/// crew, each with Accept / Decline. The sheet closes itself once the last
/// request is handled.
Future<void> showCrewRequestsSheet(BuildContext context) {
  return showCrewSheet<void>(
    context,
    builder: (_) => const CrewRequestsSheet(),
  );
}

/// The requests sheet body — reads the live crew stream, so accepting one
/// request immediately drops its row.
class CrewRequestsSheet extends ConsumerStatefulWidget {
  const CrewRequestsSheet({super.key});

  @override
  ConsumerState<CrewRequestsSheet> createState() => _CrewRequestsSheetState();
}

class _CrewRequestsSheetState extends ConsumerState<CrewRequestsSheet> {
  bool _busy = false;

  void _toast(String message, {RiseToastKind kind = RiseToastKind.info}) {
    if (!mounted) return;
    RiseToast.show(context, message, kind: kind);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      // Handled the last one? Close the sheet — nothing left to decide.
      final left = ref.read(crewServiceProvider).current.incoming;
      if (left.isEmpty && mounted) Navigator.of(context).maybePop();
    } on FriendshipException catch (e) {
      _toast(e.message, kind: RiseToastKind.error);
    } catch (_) {
      _toast('Something went wrong. Try again.', kind: RiseToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _accept(CrewMember m) => _run(() async {
        await ref.read(crewServiceProvider).acceptRequest(m.id);
        _toast('@${m.username} joined your crew.', kind: RiseToastKind.success);
      });

  Future<void> _decline(String id) =>
      _run(() => ref.read(crewServiceProvider).declineRequest(id));

  @override
  Widget build(BuildContext context) {
    final incoming =
        (ref.watch(crewProvider).value ?? CrewState.empty).incoming;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          RiseSpacing.screen, 6, RiseSpacing.screen, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Crew requests', style: RiseText.title),
          const SizedBox(height: 4),
          Text('People who asked to wake up with you.',
              style: RiseText.caption),
          const SizedBox(height: 12),
          if (incoming.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('All caught up.', style: RiseText.caption),
            )
          else
            for (final m in incoming)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    CrewAvatar(
                        username: m.username,
                        colorHex: m.avatarColor,
                        size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              m.displayName.isNotEmpty
                                  ? m.displayName
                                  : '@${m.username}',
                              style: RiseText.body
                                  .copyWith(fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          Text('@${m.username}',
                              style: RiseText.mono(
                                  size: 12, color: RiseColors.textDim),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    CrewPill('Accept',
                        onTap: _busy ? null : () => _accept(m), filled: true),
                    const SizedBox(width: 6),
                    CrewPill('Decline',
                        onTap: _busy ? null : () => _decline(m.id)),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
