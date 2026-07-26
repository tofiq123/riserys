import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/crew/crew_service.dart';
import '../../data/nudge/nudge_service.dart';
import '../../domain/clock_format.dart';
import '../../domain/crew_member.dart';
import '../../domain/crew_standing.dart';
import '../../domain/crew_status.dart';
import '../../domain/feed_item.dart';
import '../../domain/group.dart';
import '../components/confirm_dialog.dart';
import '../components/crew_avatar.dart';
import '../components/crew_entrance.dart';
import '../components/crew_sheet.dart';
import '../components/crew_status_style.dart';
import '../components/rise_buttons.dart';
import '../components/rise_card.dart';
import '../components/rise_skeleton.dart';
import '../components/section_label.dart';
import '../components/toast.dart';
import '../state/crew_providers.dart';
import '../state/feed_providers.dart';
import '../state/group_providers.dart';
import '../state/leaderboard_providers.dart';
import '../state/nudge_providers.dart';
import '../state/settings_providers.dart';
import '../state/status_providers.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'voice_composer_screen.dart';

/// One crew member's page, ordered by why you opened it.
///
/// You come here for one of two reasons: to see how their morning went, or to
/// act on it. Both used to sit at the bottom, under three stat tiles. Now
/// today's fact and all three actions are the first card, and below them sits
/// the thing the page never had — their pattern.
class FriendDetailScreen extends ConsumerStatefulWidget {
  const FriendDetailScreen({super.key, required this.member});

  final CrewMember member;

  @override
  ConsumerState<FriendDetailScreen> createState() => _FriendDetailScreenState();
}

class _FriendDetailScreenState extends ConsumerState<FriendDetailScreen> {
  bool _nudging = false;
  bool _removing = false;
  bool _cheering = false;

  CrewMember get _member => widget.member;

  void _toast(String message, {RiseToastKind kind = RiseToastKind.info}) {
    if (!mounted) return;
    RiseToast.show(context, message, kind: kind);
  }

  Future<void> _nudge() async {
    if (_nudging) return;
    setState(() => _nudging = true);
    try {
      await ref.read(nudgeServiceProvider).nudge(_member.id);
      if (mounted) {
        _toast('Nudged @${_member.username} 👋', kind: RiseToastKind.success);
      }
    } on NudgeException catch (e) {
      if (mounted) _toast(e.message, kind: RiseToastKind.error);
    } catch (_) {
      if (mounted) _toast('Could not send the nudge.', kind: RiseToastKind.error);
    } finally {
      if (mounted) setState(() => _nudging = false);
    }
  }

  Future<void> _cheer(FeedItem item) async {
    if (_cheering) return;
    setState(() => _cheering = true);
    try {
      await ref.read(feedServiceProvider).react(item.id, '🔥');
      ref.invalidate(crewFeedProvider);
      if (mounted) _toast('Cheered 🔥', kind: RiseToastKind.success);
    } catch (_) {
      if (mounted) _toast('Could not send the cheer.', kind: RiseToastKind.error);
    } finally {
      if (mounted) setState(() => _cheering = false);
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
        _toast(e.message, kind: RiseToastKind.error);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _removing = false);
        _toast('Something went wrong. Try again.', kind: RiseToastKind.error);
      }
    }
  }

  void _openVoiceComposer() {
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => VoiceComposerScreen(member: _member)));
  }

  @override
  Widget build(BuildContext context) {
    final status = (ref.watch(crewStatusesProvider).valueOrNull ??
            const <String, CrewStatus>{})[_member.id] ??
        CrewStatus.unknown;
    final board = ref.watch(leaderboardProvider);
    final standings = board.valueOrNull ?? const <CrewStanding>[];
    final theirs = standings.firstWhereOrNull((s) => s.id == _member.id);
    final mine = standings.firstWhereOrNull((s) => s.isMe);

    // Today's wake, from the feed the Crew tab already loaded.
    final feed = ref.watch(crewFeedProvider).valueOrNull ?? const <FeedItem>[];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayWake = feed.firstWhereOrNull((f) {
      if (f.userId != _member.id) return false;
      final l = f.wokeAt.toLocal();
      return DateTime(l.year, l.month, l.day).isAtSameMomentAs(today);
    });

    return Scaffold(
      backgroundColor: RiseColors.appBg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              RiseSpacing.screen, 8, RiseSpacing.screen, 40),
          children: [
            CrewEntrance(index: 0, child: _navBar()),
            const SizedBox(height: 6),
            CrewEntrance(index: 1, child: _identity(status)),
            const SizedBox(height: 24),
            CrewEntrance(index: 2, child: _todayCard(status, todayWake)),
            const SizedBox(height: 26),
            CrewEntrance(
              index: 3,
              child: board.isLoading && !board.hasValue
                  ? const _StatsSkeleton()
                  : theirs == null
                      ? _noStats()
                      : _theirMornings(theirs, mine),
            ),
            const SizedBox(height: 26),
            CrewEntrance(index: 4, child: _inCommon()),
          ],
        ),
      ),
    );
  }

  Widget _navBar() => Row(
        children: [
          Semantics(
            button: true,
            label: 'Back',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).maybePop(),
              child: Container(
                width: 44,
                height: 44,
                alignment: Alignment.centerLeft,
                child: Icon(Icons.arrow_back, color: RiseColors.text, size: 22),
              ),
            ),
          ),
          const Spacer(),
          Semantics(
            button: true,
            label: 'More options',
            child: GestureDetector(
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
          size: 80,
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
                decoration:
                    BoxDecoration(color: style.color, shape: BoxShape.circle),
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

  /// Today's fact and the three actions, on one card. Mid-mission is the one
  /// moment a cheer is genuinely useful, so it gets its own treatment.
  Widget _todayCard(CrewStatus status, FeedItem? wake) {
    final waking = status == CrewStatus.waking;
    final use24h =
        ref.watch(currentSettingsProvider.select((s) => s.use24HourTime));

    if (waking) {
      return Container(
        key: const Key('friend-today-waking'),
        padding: const EdgeInsets.all(RiseSpacing.screen),
        decoration: BoxDecoration(
          color: RiseColors.card,
          borderRadius: BorderRadius.circular(RiseRadii.lg),
          border: Border.all(color: RiseColors.waking),
          boxShadow: RiseShadows.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('RIGHT NOW',
                style: RiseText.sectionLabel.copyWith(color: RiseColors.waking)),
            const SizedBox(height: 10),
            Text("$_first's alarm is going.",
                style: RiseText.title.copyWith(fontSize: 17)),
            const SizedBox(height: 4),
            Text('A cheer lands while they are still getting up.',
                style: RiseText.caption),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                key: const Key('friend-nudge'),
                label: 'Nudge',
                icon: Icons.notifications_active_outlined,
                onPressed: _nudging ? null : _nudge,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SecondaryButton(
                label: 'Send a voice clip',
                icon: Icons.mic_none,
                onPressed: _openVoiceComposer,
              ),
            ),
          ],
        ),
      );
    }

    return RiseCard(
      key: const Key('friend-today'),
      padding: const EdgeInsets.all(RiseSpacing.screen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('TODAY', style: RiseText.sectionLabel),
          const SizedBox(height: 10),
          if (wake == null)
            Text('No wake logged yet.', style: RiseText.body)
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(
                      formatClock(wake.wokeAt.toLocal().hour,
                          wake.wokeAt.toLocal().minute,
                          use24h: use24h),
                      style:
                          RiseText.mono(size: 26, weight: FontWeight.w600),
                      maxLines: 1),
                ),
                const SizedBox(width: 10),
                Text(wake.onTime ? 'on time' : 'woke up',
                    style: RiseText.caption.copyWith(
                        color: wake.onTime
                            ? RiseColors.positive
                            : RiseColors.textDim,
                        fontWeight:
                            wake.onTime ? FontWeight.w600 : FontWeight.w400)),
                if (wake.streak > 0) ...[
                  const Spacer(),
                  Text('🔥${wake.streak}',
                      style: RiseText.mono(
                          size: 13,
                          weight: FontWeight.w600,
                          color: RiseColors.textDim)),
                ],
              ],
            ),
            if (wake.reactions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                  'Your crew left '
                  '${wake.reactions.map((r) => "${r.emoji}${r.count}").join(" ")}.',
                  style: RiseText.caption),
            ],
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              if (wake != null) ...[
                Expanded(
                  child: SecondaryButton(
                    key: const Key('friend-cheer'),
                    label: 'Cheer',
                    icon: Icons.local_fire_department_outlined,
                    onPressed: _cheering ? null : () => _cheer(wake),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: PrimaryButton(
                  key: const Key('friend-nudge'),
                  label: 'Nudge',
                  icon: Icons.notifications_active_outlined,
                  onPressed: _nudging ? null : _nudge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: SecondaryButton(
              key: const Key('friend-voice'),
              label: 'Send a voice clip',
              icon: Icons.mic_none,
              onPressed: _openVoiceComposer,
            ),
          ),
        ],
      ),
    );
  }

  String get _first => _member.displayName.isNotEmpty
      ? _member.displayName.split(' ').first
      : '@${_member.username}';

  Widget _theirMornings(CrewStanding theirs, CrewStanding? mine) {
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
  }

  Widget _statTiles(CrewStanding s) {
    final onTimePct = (s.stats.onTimeRate * 100).round();
    return Row(
      children: [
        Expanded(
          child: _statTile(
            value: '${s.stats.currentStreak}',
            label: 'day run',
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
        ? "You're neck and neck — ${mine.stats.currentStreak}-day runs each."
        : ahead
            ? '$_first is ahead by $gap ${gap == 1 ? 'day' : 'days'}. '
                'Catch up together.'
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

  /// Nothing to chart yet. Says what appears and when — and still offers the
  /// actions, because a new friend is exactly who you want to nudge.
  Widget _noStats() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Their mornings'),
          const SizedBox(height: 12),
          RiseCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
              child: Column(
                children: [
                  Icon(Icons.insights_outlined,
                      size: 30, color: RiseColors.textFaint),
                  const SizedBox(height: 10),
                  Text('No stats to show yet',
                      style:
                          RiseText.body.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                      'Their run and on-time rate appear here once they start '
                      'logging wake-ups.',
                      textAlign: TextAlign.center,
                      style: RiseText.caption),
                ],
              ),
            ),
          ),
        ],
      );

  /// The ties: which groups you share, so a friend page connects back into the
  /// rest of the app instead of dead-ending.
  Widget _inCommon() {
    final groups = ref.watch(myGroupsProvider).valueOrNull ?? const <Group>[];
    final shared = [
      for (final g in groups)
        if ((ref.watch(groupMembersProvider(g.id)).valueOrNull ?? const [])
            .any((m) => m.id == _member.id))
          g
    ];
    if (shared.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('In common'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final g in shared)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: RiseColors.card,
                  borderRadius: BorderRadius.circular(RiseRadii.pill),
                  border: Border.all(color: RiseColors.border),
                  boxShadow: RiseShadows.card,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.groups_outlined,
                        size: 15, color: RiseColors.textDim),
                    const SizedBox(width: 7),
                    Text(g.name,
                        style: RiseText.body.copyWith(
                            fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// The stat tiles' loading shape, so nothing moves when the board lands.
class _StatsSkeleton extends StatelessWidget {
  const _StatsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Their mornings'),
        const SizedBox(height: 12),
        Row(
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              const Expanded(
                  child: RiseSkeleton(height: 66, radius: RiseRadii.base)),
            ],
          ],
        ),
      ],
    );
  }
}
