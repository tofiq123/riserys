import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/crew/crew_service.dart';
import '../../data/nudge/nudge_service.dart';
import '../../domain/crew_member.dart';
import '../../domain/crew_standing.dart';
import '../../domain/crew_status.dart';
import '../components/confirm_dialog.dart';
import '../components/crew_avatar.dart';
import '../components/crew_entrance.dart';
import '../components/crew_sheet.dart';
import '../components/crew_status_style.dart';
import '../components/rise_buttons.dart';
import '../components/rise_card.dart';
import '../components/section_label.dart';
import '../components/toast.dart';
import '../state/crew_providers.dart';
import '../state/leaderboard_providers.dart';
import '../state/nudge_providers.dart';
import '../state/status_providers.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'voice_composer_screen.dart';

/// One crew member's page: a large avatar wrapped in their live status ring,
/// stat tiles (streak / on-time / best) in mono numerals, a you-two
/// comparison, and the actions — Nudge (primary) and a voice clip
/// (secondary). Removing them hides behind the "…" overflow, still guarded by
/// the shared confirm dialog.
///
/// Reads only the existing crew/status/leaderboard providers — no new
/// fetching. Missing stats degrade to a gentle placeholder.
class FriendDetailScreen extends ConsumerStatefulWidget {
  const FriendDetailScreen({super.key, required this.member});

  final CrewMember member;

  @override
  ConsumerState<FriendDetailScreen> createState() => _FriendDetailScreenState();
}

class _FriendDetailScreenState extends ConsumerState<FriendDetailScreen> {
  bool _nudging = false;
  bool _removing = false;

  CrewMember get _member => widget.member;

  void _snack(String message, {RiseToastKind kind = RiseToastKind.info}) {
    if (!mounted) return;
    RiseToast.show(context, message, kind: kind);
  }

  Future<void> _nudge() async {
    if (_nudging) return;
    setState(() => _nudging = true);
    try {
      await ref.read(nudgeServiceProvider).nudge(_member.id);
      if (mounted) {
        _snack('Nudged @${_member.username} 👋', kind: RiseToastKind.success);
      }
    } on NudgeException catch (e) {
      if (mounted) _snack(e.message, kind: RiseToastKind.error);
    } catch (_) {
      if (mounted) {
        _snack('Could not send the nudge.', kind: RiseToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _nudging = false);
    }
  }

  Future<void> _openOverflow() async {
    final remove = await showCrewSheet<bool>(
      context,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(
            RiseSpacing.screen, 6, RiseSpacing.screen, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('@${_member.username}', style: RiseText.title),
            const SizedBox(height: 10),
            GestureDetector(
              key: const Key('friend-remove-action'),
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(sheetContext).pop(true),
              child: Container(
                constraints: const BoxConstraints(minHeight: 52),
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    Icon(Icons.person_remove_outlined,
                        size: 20, color: RiseColors.danger),
                    const SizedBox(width: 12),
                    Text('Remove from crew',
                        style: RiseText.body.copyWith(
                            color: RiseColors.danger,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (remove == true) await _remove();
  }

  Future<void> _remove() async {
    if (_removing || !mounted) return;
    final ok = await showConfirmDialog(
      context,
      title: 'Remove @${_member.username}?',
      message: "You'll stop seeing each other's wake status and streaks. "
          'You can add them back anytime.',
      confirmLabel: 'Remove',
      danger: true,
    );
    if (!ok) return;
    setState(() => _removing = true);
    try {
      await ref.read(crewServiceProvider).removeFriend(_member.id);
      if (mounted) Navigator.of(context).maybePop();
    } on FriendshipException catch (e) {
      if (mounted) {
        setState(() => _removing = false);
        _snack(e.message, kind: RiseToastKind.error);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _removing = false);
        _snack('Something went wrong. Try again.', kind: RiseToastKind.error);
      }
    }
  }

  void _openVoiceComposer() {
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => VoiceComposerScreen(member: _member)));
  }

  @override
  Widget build(BuildContext context) {
    final status = (ref.watch(crewStatusesProvider).value ??
            const <String, CrewStatus>{})[_member.id] ??
        CrewStatus.unknown;
    final board = ref.watch(leaderboardProvider);

    return Scaffold(
      backgroundColor: RiseColors.appBg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              RiseSpacing.screen, 8, RiseSpacing.screen, 40),
          children: [
            CrewEntrance(index: 0, child: _navBar()),
            const SizedBox(height: 10),
            CrewEntrance(index: 1, child: _identity(status)),
            const SizedBox(height: 26),
            CrewEntrance(
              index: 2,
              child: board.when(
                data: (standings) {
                  final theirs =
                      standings.firstWhereOrNull((s) => s.id == _member.id);
                  final mine = standings.firstWhereOrNull((s) => s.isMe);
                  if (theirs == null) return _statsUnavailable();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionLabel('Their mornings'),
                      const SizedBox(height: 12),
                      _statTiles(theirs),
                      if (mine != null) ...[
                        const SizedBox(height: 26),
                        const SectionLabel('You two'),
                        const SizedBox(height: 12),
                        _mutualCard(mine, theirs),
                      ],
                    ],
                  );
                },
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                ),
                error: (_, __) => _statsUnavailable(),
              ),
            ),
            const SizedBox(height: 30),
            CrewEntrance(index: 3, child: _actions()),
          ],
        ),
      ),
    );
  }

  Widget _navBar() => Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).maybePop(),
            child: Container(
              width: 44,
              height: 44,
              alignment: Alignment.centerLeft,
              child: Icon(Icons.arrow_back, color: RiseColors.text, size: 22),
            ),
          ),
          const Spacer(),
          GestureDetector(
            key: const Key('friend-overflow'),
            behavior: HitTestBehavior.opaque,
            onTap: _removing ? null : _openOverflow,
            child: Container(
              width: 44,
              height: 44,
              alignment: Alignment.centerRight,
              child:
                  Icon(Icons.more_horiz, color: RiseColors.textDim, size: 22),
            ),
          ),
        ],
      );

  Widget _identity(CrewStatus status) {
    final style = crewStatusStyle(status);
    return Column(
      children: [
        CrewAvatar(
          username: _member.username,
          colorHex: _member.avatarColor,
          size: 76,
          ring: status,
        ),
        const SizedBox(height: 14),
        Text(
          _member.displayName.isNotEmpty
              ? _member.displayName
              : '@${_member.username}',
          style: RiseText.title.copyWith(fontSize: 21),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text('@${_member.username}',
            style: RiseText.mono(size: 13, color: RiseColors.textDim),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: RiseColors.card,
            borderRadius: BorderRadius.circular(RiseRadii.pill),
            border: Border.all(color: RiseColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                    color: style.color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 7),
              Text(style.line,
                  style: RiseText.caption.copyWith(
                      color: style.color, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statTiles(CrewStanding s) {
    final onTimePct = (s.stats.onTimeRate * 100).round();
    return Row(
      children: [
        Expanded(
          child: _statTile(
            value: '${s.stats.currentStreak}',
            label: 'day streak',
            flame: s.stats.currentStreak >= 1,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _statTile(
            value: s.stats.totalWakes == 0 ? '—' : '$onTimePct%',
            label: 'on time',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _statTile(value: '${s.stats.bestStreak}', label: 'best'),
        ),
      ],
    );
  }

  Widget _statTile(
      {required String value, required String label, bool flame = false}) {
    return RiseCard(
      radius: RiseRadii.base,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (flame) ...[
                const Text('🔥', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 4),
              ],
              Text(value,
                  style: RiseText.mono(size: 22, weight: FontWeight.w600),
                  maxLines: 1),
            ],
          ),
          const SizedBox(height: 3),
          Text(label,
              style: RiseText.caption.copyWith(fontSize: 11.5),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _mutualCard(CrewStanding mine, CrewStanding theirs) {
    final ahead = theirs.stats.currentStreak > mine.stats.currentStreak;
    final tied = theirs.stats.currentStreak == mine.stats.currentStreak;
    final gap = (theirs.stats.currentStreak - mine.stats.currentStreak).abs();
    final line = tied
        ? "You're neck and neck — ${mine.stats.currentStreak}-day streaks each."
        : ahead
            ? '@${_member.username} is ahead by $gap '
                '${gap == 1 ? 'day' : 'days'}. Catch up together.'
            : "You're ahead by $gap ${gap == 1 ? 'day' : 'days'}. "
                'Keep it going.';
    return RiseCard(
      padding: const EdgeInsets.all(RiseSpacing.screen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _mutualStat('${mine.stats.currentStreak}', 'you'),
              Container(width: 1, height: 36, color: RiseColors.divider),
              _mutualStat(
                  '${theirs.stats.currentStreak}', '@${_member.username}'),
            ],
          ),
          const SizedBox(height: 14),
          Text(line, style: RiseText.caption),
        ],
      ),
    );
  }

  Widget _mutualStat(String value, String label) => Expanded(
        child: Column(
          children: [
            Text(value,
                style: RiseText.mono(size: 24, weight: FontWeight.w600),
                maxLines: 1),
            const SizedBox(height: 3),
            Text(label,
                style: RiseText.caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      );

  Widget _statsUnavailable() => RiseCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
          child: Column(
            children: [
              Icon(Icons.insights_outlined,
                  size: 30, color: RiseColors.textFaint),
              const SizedBox(height: 10),
              Text('No stats to show yet',
                  style: RiseText.body.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                  'Their streak and on-time rate appear here once they start '
                  'logging wake-ups.',
                  textAlign: TextAlign.center,
                  style: RiseText.caption),
            ],
          ),
        ),
      );

  Widget _actions() => Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(
              label: 'Nudge',
              icon: Icons.notifications_active_outlined,
              onPressed: _nudging ? null : _nudge,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: SecondaryButton(
              label: 'Send a voice clip',
              icon: Icons.mic_none,
              onPressed: _openVoiceComposer,
            ),
          ),
        ],
      );
}
