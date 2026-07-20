import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/crew/crew_service.dart';
import '../../data/nudge/nudge_service.dart';
import '../../domain/crew_member.dart';
import '../../domain/crew_standing.dart';
import '../../domain/crew_status.dart';
import '../components/rise_card.dart';
import '../components/section_label.dart';
import '../state/crew_providers.dart';
import '../state/leaderboard_providers.dart';
import '../state/nudge_providers.dart';
import '../state/status_providers.dart';
import '../theme/avatar_color.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// A single crew member's page: their live status, streak, on-time %, and how
/// you two stack up, plus the same nudge / remove actions as the Crew list.
///
/// Reads only from the existing crew/status/leaderboard providers — no new
/// fetching. Any field the backend doesn't expose (stats before the leaderboard
/// has loaded, an unknown status) simply degrades to a gentle placeholder.
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

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _nudge() async {
    if (_nudging) return;
    setState(() => _nudging = true);
    try {
      await ref.read(nudgeServiceProvider).nudge(_member.id);
      if (mounted) _snack('Nudged @${_member.username} 👋');
    } on NudgeException catch (e) {
      if (mounted) _snack(e.message);
    } catch (_) {
      if (mounted) _snack('Could not send the nudge.');
    } finally {
      if (mounted) setState(() => _nudging = false);
    }
  }

  Future<void> _remove() async {
    if (_removing) return;
    setState(() => _removing = true);
    try {
      await ref.read(crewServiceProvider).removeFriend(_member.id);
      if (mounted) Navigator.of(context).maybePop();
    } on FriendshipException catch (e) {
      if (mounted) {
        setState(() => _removing = false);
        _snack(e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _removing = false);
        _snack('Something went wrong. Try again.');
      }
    }
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
            _header(),
            const SizedBox(height: 20),
            _identityCard(status),
            const SizedBox(height: 24),
            const SectionLabel('Their wake-ups'),
            const SizedBox(height: 12),
            board.when(
              data: (standings) {
                final theirs =
                    standings.firstWhereOrNull((s) => s.id == _member.id);
                final mine = standings.firstWhereOrNull((s) => s.isMe);
                if (theirs == null) return _statsUnavailable();
                return Column(
                  children: [
                    _statsCard(theirs),
                    if (mine != null) ...[
                      const SizedBox(height: 24),
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
            const SizedBox(height: 28),
            _actions(),
          ],
        ),
      ),
    );
  }

  Widget _header() => Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).maybePop(),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Icon(Icons.arrow_back, color: RiseColors.text, size: 22),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                _member.displayName.isNotEmpty
                    ? _member.displayName
                    : '@${_member.username}',
                style: RiseText.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      );

  Widget _identityCard(CrewStatus status) => RiseCard(
        padding: const EdgeInsets.all(RiseSpacing.screen),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: avatarColorFromHex(_member.avatarColor),
                  shape: BoxShape.circle),
              child: Text(
                (_member.username.isNotEmpty ? _member.username : '?')
                    .characters
                    .first
                    .toUpperCase(),
                style: RiseText.title.copyWith(
                    color: RiseColors.primaryText, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('@${_member.username}',
                      style: RiseText.mono(size: 13, color: RiseColors.textDim),
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                            color: _statusColor(status),
                            shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Text(_statusLine(status),
                          style: RiseText.body
                              .copyWith(color: _statusColor(status))),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _statsCard(CrewStanding s) {
    final onTimePct = (s.stats.onTimeRate * 100).round();
    return RiseCard(
      padding: const EdgeInsets.all(RiseSpacing.screen),
      child: Row(
        children: [
          _stat('${s.stats.currentStreak}',
              s.stats.currentStreak == 1 ? 'day streak' : 'day streak'),
          _divider(),
          _stat('${s.stats.bestStreak}', 'best'),
          _divider(),
          _stat(s.stats.totalWakes == 0 ? '—' : '$onTimePct%', 'on time'),
        ],
      ),
    );
  }

  Widget _mutualCard(CrewStanding mine, CrewStanding theirs) {
    final ahead = theirs.stats.currentStreak > mine.stats.currentStreak;
    final tied = theirs.stats.currentStreak == mine.stats.currentStreak;
    final line = tied
        ? 'You\'re neck and neck — ${mine.stats.currentStreak}-day streaks each.'
        : ahead
            ? '@${_member.username} is ahead by '
                '${theirs.stats.currentStreak - mine.stats.currentStreak} '
                '${theirs.stats.currentStreak - mine.stats.currentStreak == 1 ? 'day' : 'days'}. '
                'Catch up together.'
            : 'You\'re ahead by '
                '${mine.stats.currentStreak - theirs.stats.currentStreak} '
                '${mine.stats.currentStreak - theirs.stats.currentStreak == 1 ? 'day' : 'days'}. '
                'Keep it going.';
    return RiseCard(
      padding: const EdgeInsets.all(RiseSpacing.screen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _stat('${mine.stats.currentStreak}', 'you'),
              _divider(),
              _stat('${theirs.stats.currentStreak}', '@${_member.username}'),
            ],
          ),
          const SizedBox(height: 14),
          Text(line, style: RiseText.caption),
        ],
      ),
    );
  }

  Widget _statsUnavailable() => RiseCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
          child: Column(
            children: [
              const Icon(Icons.insights_outlined,
                  size: 30, color: RiseColors.textFaint),
              const SizedBox(height: 10),
              Text('No stats to show yet',
                  style: RiseText.body.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Their streak and on-time rate appear here once they start '
                  'logging wake-ups.',
                  textAlign: TextAlign.center, style: RiseText.caption),
            ],
          ),
        ),
      );

  Widget _actions() => Row(
        children: [
          Expanded(
            child: _button('Nudge', _nudging ? null : _nudge, filled: true),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _button('Remove', _removing ? null : _remove, danger: true),
          ),
        ],
      );

  Widget _stat(String value, String label) => Expanded(
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

  Widget _divider() =>
      Container(width: 1, height: 36, color: RiseColors.divider);

  Widget _button(String label, VoidCallback? onTap,
      {bool filled = false, bool danger = false}) {
    final bg = filled ? RiseColors.primary : RiseColors.card;
    final fg = danger
        ? RiseColors.danger
        : filled
            ? RiseColors.primaryText
            : RiseColors.text;
    return Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(RiseRadii.sm),
            border: filled ? null : Border.all(color: RiseColors.border),
          ),
          child: Text(label,
              style: RiseText.body.copyWith(
                  color: fg, fontWeight: FontWeight.w600, fontSize: 14)),
        ),
      ),
    );
  }

  static Color _statusColor(CrewStatus s) => switch (s) {
        CrewStatus.waking => RiseColors.waking,
        CrewStatus.awake => RiseColors.positive,
        CrewStatus.asleep => RiseColors.asleep,
        CrewStatus.unknown => RiseColors.textFaint,
      };

  static String _statusLine(CrewStatus s) => switch (s) {
        CrewStatus.waking => 'Waking up now',
        CrewStatus.awake => 'Up and about',
        CrewStatus.asleep => 'Probably asleep',
        CrewStatus.unknown => 'Status unavailable',
      };
}
