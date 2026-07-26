import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/group/group_service.dart';
import '../../data/invite_links.dart';
import '../../domain/crew_member.dart';
import '../../domain/crew_score.dart';
import '../../domain/crew_standing.dart';
import '../../domain/group.dart';
import '../../domain/group_challenge.dart';
import '../../domain/group_roster.dart';
import '../components/crew_avatar.dart';
import '../components/crew_entrance.dart';
import '../components/crew_pill.dart';
import '../components/crew_sheet.dart';
import '../components/rise_buttons.dart';
import '../components/rise_card.dart';
import '../components/rise_skeleton.dart';
import '../components/section_label.dart';
import '../components/toast.dart';
import '../state/auth_providers.dart';
import '../state/group_providers.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// One group's page: its invite code (to share), the collective group score,
/// a leaderboard reusing the per-member streak/stats data, the roster, and
/// owner/member actions (rename, remove member, leave / delete). Reads via
/// the existing group providers.
class GroupDetailScreen extends ConsumerStatefulWidget {
  const GroupDetailScreen({super.key, required this.group});

  final Group group;

  @override
  ConsumerState<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends ConsumerState<GroupDetailScreen> {
  late Group _group = widget.group;
  bool _busy = false;

  String get _gid => _group.id;

  void _snack(String message, {RiseToastKind kind = RiseToastKind.info}) {
    if (!mounted) return;
    RiseToast.show(context, message, kind: kind);
  }

  void _refresh() {
    ref.invalidate(myGroupsProvider);
    ref.invalidate(groupMembersProvider(_gid));
    ref.invalidate(groupLeaderboardProvider(_gid));
    ref.invalidate(groupChallengeProvider(_gid));
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on GroupException catch (e) {
      _snack(e.message, kind: RiseToastKind.error);
    } catch (_) {
      _snack('Something went wrong. Try again.', kind: RiseToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: _group.inviteCode));
    _snack('Invite code copied. Share it with your crew.',
        kind: RiseToastKind.success);
  }

  /// Opens the OS share sheet with a tappable deep link — the recipient taps it,
  /// Riserys opens, and they join this group straight away (no code to type).
  Future<void> _shareLink() async {
    final link = buildInviteLink(_group.inviteCode);
    try {
      await SharePlus.instance.share(ShareParams(
        text: 'Join my Riserys group "${_group.name}" — we wake up together.\n$link',
        subject: 'Join my Riserys crew',
      ));
    } catch (_) {
      // Share sheet unavailable → fall back to copying the code, never crash.
      await _copyCode();
    }
  }

  Future<void> _rename() async {
    final controller = TextEditingController(text: _group.name);
    final next = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: RiseColors.card,
        title: Text('Rename group', style: RiseText.title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          style: RiseText.body,
          cursorColor: RiseColors.primary,
          decoration: const InputDecoration(hintText: 'Group name'),
        ),
        actions: [
          GhostButton(
            label: 'Cancel',
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Text('Save',
                  style: RiseText.body.copyWith(
                    color: RiseColors.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  )),
            ),
          ),
        ],
      ),
    );
    controller.dispose();
    if (next == null || next.isEmpty || next == _group.name) return;
    await _run(() async {
      await ref.read(groupServiceProvider).renameGroup(_gid, next);
      if (!mounted) return;
      setState(() => _group = _group.copyWith(name: next));
      _refresh();
      _snack('Renamed to "$next".', kind: RiseToastKind.success);
    });
  }

  Future<void> _removeMember(CrewMember m) => _run(() async {
        await ref.read(groupServiceProvider).removeMember(_gid, m.id);
        _refresh();
        if (mounted) {
          _snack('Removed @${m.username}.', kind: RiseToastKind.success);
        }
      });

  Future<void> _leave() => _run(() async {
        await ref.read(groupServiceProvider).leaveGroup(_gid);
        ref.invalidate(myGroupsProvider);
        if (mounted) Navigator.of(context).maybePop();
      });

  Future<void> _delete() => _run(() async {
        await ref.read(groupServiceProvider).deleteGroup(_gid);
        ref.invalidate(myGroupsProvider);
        if (mounted) Navigator.of(context).maybePop();
      });

  Future<void> _startRace() => _run(() async {
        await ref.read(groupServiceProvider).startChallenge(_gid);
        ref.invalidate(groupChallengeProvider(_gid));
        if (mounted) {
          _snack('Streak race started 🔥', kind: RiseToastKind.success);
        }
      });

  Future<void> _endRace(GroupChallenge c) => _run(() async {
        await ref.read(groupServiceProvider).endChallenge(c.id);
        ref.invalidate(groupChallengeProvider(_gid));
        if (mounted) _snack('Race ended.', kind: RiseToastKind.success);
      });

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(accountProvider).value?.id;
    final board = ref.watch(groupLeaderboardProvider(_gid));
    final members = ref.watch(groupMembersProvider(_gid));
    final challengeAsync = ref.watch(groupChallengeProvider(_gid));
    final challenge = challengeAsync.value;

    final standings = board.value ?? const <CrewStanding>[];
    // First load (nothing cached yet) → skeleton rows; afterwards data renders
    // even while a refresh is in flight.
    final loading = (board.isLoading && !board.hasValue) ||
        (members.isLoading && !members.hasValue);
    final failed = board.hasError && members.hasError;
    final roster = mergeRoster(standings, members.value ?? const []);
    // While a race runs, each ranked row carries its in/out chip — the same
    // list, one more column, instead of a third list of the same people.
    final race = (challenge != null && challenge.isActive)
        ? {
            for (final r in challengeStandings(
                startedAt: challenge.startedAt,
                now: DateTime.now(),
                standings: standings))
              r.standing.id: r.inRace
          }
        : null;

    return Scaffold(
      backgroundColor: RiseColors.appBg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              RiseSpacing.screen, 8, RiseSpacing.screen, 40),
          children: [
            CrewEntrance(index: 0, child: _header()),
            const SizedBox(height: 18),
            CrewEntrance(index: 1, child: _inviteCard()),
            const SizedBox(height: 26),
            if (standings.isNotEmpty) ...[
              CrewEntrance(
                index: 2,
                child: _scoreCard(computeCrewScore(standings),
                    challenge: challenge, standings: standings),
              ),
              const SizedBox(height: 14),
            ],
            CrewEntrance(
              index: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionLabel('Members'),
                  const SizedBox(height: 12),
                  if (loading)
                    const Column(children: [
                      _MemberRowSkeleton(),
                      _MemberRowSkeleton(),
                      _MemberRowSkeleton(),
                    ])
                  else if (failed)
                    Text('Could not load members.', style: RiseText.caption)
                  else if (roster.isEmpty)
                    Text('No members to show yet.', style: RiseText.caption)
                  else
                    Column(children: [
                      for (final entry in roster)
                        _memberRow(entry, me, race: race),
                    ]),
                ],
              ),
            ),
            if (challenge == null && challengeAsync.hasValue) ...[
              const SizedBox(height: 16),
              CrewEntrance(index: 4, child: _raceCta()),
            ],
            const SizedBox(height: 30),
            CrewEntrance(index: 5, child: _footerAction()),
          ],
        ),
      ),
    );
  }

  Widget _header() => Row(
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
          const SizedBox(width: 4),
          Expanded(
            child: Text(_group.name,
                style: RiseText.title.copyWith(fontSize: 19),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          if (_group.isOwner)
            Semantics(
              button: true,
              label: 'Rename group',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _busy ? null : _rename,
                child: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.centerRight,
                  child: Icon(Icons.edit_outlined,
                      color: RiseColors.textDim, size: 20),
                ),
              ),
            ),
        ],
      );

  Widget _inviteCard() => RiseCard(
        padding: const EdgeInsets.all(RiseSpacing.screen),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Invite code',
                      style:
                          RiseText.caption.copyWith(color: RiseColors.textDim)),
                  const SizedBox(height: 4),
                  Text(_group.inviteCode,
                      style: RiseText.mono(
                          size: 24,
                          weight: FontWeight.w600,
                          letterSpacing: 1.5),
                      maxLines: 1),
                ],
              ),
            ),
            const SizedBox(width: 12),
            CrewPill('Share', onTap: _shareLink, filled: true),
            const SizedBox(width: 8),
            CrewPill('Copy', onTap: _copyCode, filled: false),
          ],
        ),
      );

  Widget _scoreCard(CrewScore score,
      {GroupChallenge? challenge, required List<CrewStanding> standings}) {
    final you = score.you;
    final sub = you == null
        ? '${score.memberCount} climbing together.'
        : 'Your part: ${you.points} pts · ${you.sharePercent}% of the group.';
    final c = challenge;
    final live = c != null && c.isActive;
    String? raceLine;
    if (live) {
      final now = DateTime.now();
      final day = challengeDayCount(startedAt: c.startedAt, now: now);
      final alive = challengeStandings(
              startedAt: c.startedAt, now: now, standings: standings)
          .where((r) => r.inRace)
          .length;
      raceLine = 'Streak race · Day $day · $alive still standing';
    }
    return Container(
      padding: const EdgeInsets.all(RiseSpacing.screen),
      decoration: BoxDecoration(
        color: RiseColors.primary,
        borderRadius: BorderRadius.circular(RiseRadii.base),
        boxShadow: RiseShadows.primary,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('${score.crewTotal}',
                  style: RiseText.mono(
                      size: 38,
                      weight: FontWeight.w600,
                      color: RiseColors.primaryText)),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text('group score',
                    style:
                        RiseText.body.copyWith(color: RiseColors.primaryText)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Opacity(
            opacity: 0.75,
            child: Text(sub,
                style:
                    RiseText.caption.copyWith(color: RiseColors.primaryText)),
          ),
          if (raceLine != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('🔥', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(raceLine,
                      style: RiseText.caption.copyWith(
                          color: RiseColors.primaryText,
                          fontWeight: FontWeight.w600)),
                ),
                if (_group.isOwner && live)
                  GestureDetector(
                    key: const Key('end-race-action'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _busy ? null : () => _endRace(c),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 4),
                      child: Opacity(
                        opacity: 0.75,
                        child: Text('End race',
                            style: RiseText.caption.copyWith(
                                color: RiseColors.primaryText,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// The "start a race" affordance, shown only while no race runs: a real CTA
  /// for the owner, a quiet explainer for members.
  Widget _raceCta() {
    if (!_group.isOwner) {
      return RiseCard(
        child: Row(
          children: [
            const Text('🔥', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                  'No streak race running — the group owner can start one.',
                  style: RiseText.caption),
            ),
          ],
        ),
      );
    }
    return RiseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Everyone keeps their streak alive — last one standing wins. '
              'Kind, not cut-throat.',
              style: RiseText.caption),
          const SizedBox(height: 10),
          PrimaryButton(
            label: 'Start a streak race',
            onPressed: _busy ? null : _startRace,
          ),
        ],
      ),
    );
  }

  /// One merged member row: rank, avatar, identity, race chip (when a race
  /// runs), streak — and the owner's remove action behind a per-row overflow.
  /// Every person on this page appears exactly once, here.
  Widget _memberRow(RosterEntry entry, String? me,
      {required Map<String, bool>? race}) {
    final m = entry.member;
    final s = entry.standing;
    final isOwner = m.id == _group.ownerId;
    final isSelf = m.id == me || (s?.isMe ?? false);
    final canRemove = _group.isOwner && !isSelf;
    final onTimePct =
        s == null ? null : (s.stats.onTimeRate * 100).round();
    final inRace = race?[m.id];

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(RiseSpacing.cardPad),
        decoration: BoxDecoration(
          color: isSelf ? RiseColors.accentSoft : RiseColors.card,
          borderRadius: BorderRadius.circular(RiseRadii.base),
          border: Border.all(
              color: isSelf ? RiseColors.accent : RiseColors.border),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: Text(entry.rank == null ? '·' : '${entry.rank}',
                  style: RiseText.mono(
                      size: 15,
                      weight: FontWeight.w600,
                      color: entry.rank == null
                          ? RiseColors.textFaint
                          : RiseColors.text)),
            ),
            const SizedBox(width: 8),
            CrewAvatar(
                username: m.username, colorHex: m.avatarColor, size: 34),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                            m.displayName.isNotEmpty
                                ? m.displayName
                                : '@${m.username}',
                            style: RiseText.body
                                .copyWith(fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (isOwner) ...[
                        const SizedBox(width: 6),
                        _badge('Owner'),
                      ],
                    ],
                  ),
                  Text(
                      onTimePct == null
                          ? '@${m.username} · no wakes yet'
                          : '@${m.username} · $onTimePct% on time',
                      style: RiseText.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (inRace != null) ...[
              const SizedBox(width: 6),
              Text(inRace ? '🔥' : '💤',
                  style: const TextStyle(fontSize: 15)),
            ],
            if (s != null) ...[
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${s.stats.currentStreak}',
                      style:
                          RiseText.mono(size: 18, weight: FontWeight.w600)),
                  Text('day streak',
                      style: RiseText.caption.copyWith(fontSize: 10)),
                ],
              ),
            ],
            if (canRemove)
              Semantics(
                button: true,
                label: 'Member actions for @${m.username}',
                child: GestureDetector(
                  key: Key('member-overflow-${m.username}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _busy ? null : () => _memberActions(m),
                  child: Container(
                    width: 36,
                    height: 44,
                    alignment: Alignment.centerRight,
                    child: Icon(Icons.more_vert,
                        size: 18, color: RiseColors.textFaint),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _memberActions(CrewMember m) async {
    final remove = await showCrewSheet<bool>(
      context,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(
            RiseSpacing.screen, 6, RiseSpacing.screen, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('@${m.username}', style: RiseText.title),
            const SizedBox(height: 10),
            GestureDetector(
              key: const Key('member-remove-action'),
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
                    Text('Remove from group',
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
    if (remove == true) await _removeMember(m);
  }

  Widget _footerAction() => _group.isOwner
      ? _wideButton('Delete group', _busy ? null : _delete)
      : _wideButton('Leave group', _busy ? null : _leave);

  Widget _badge(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: RiseColors.accentSoft,
          borderRadius: BorderRadius.circular(RiseRadii.sm),
          border: Border.all(color: RiseColors.border),
        ),
        child: Text(label,
            style: RiseText.caption.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: RiseColors.textDim)),
      );

  Widget _wideButton(String label, VoidCallback? onTap) {
    return Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: RiseColors.card,
            borderRadius: BorderRadius.circular(RiseRadii.base),
            border: Border.all(color: RiseColors.danger),
          ),
          child: Text(label,
              style: RiseText.body.copyWith(
                  color: RiseColors.danger,
                  fontWeight: FontWeight.w600,
                  fontSize: 14)),
        ),
      ),
    );
  }
}

/// One member row's loading shape: rank dot, avatar ghost, two text bars.
class _MemberRowSkeleton extends StatelessWidget {
  const _MemberRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RiseCard(
        child: Row(
          children: [
            const SizedBox(width: 22),
            const SizedBox(width: 8),
            const RiseSkeletonCircle(size: 34),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  RiseSkeleton(width: 120, height: 12),
                  SizedBox(height: 7),
                  RiseSkeleton(width: 150, height: 10),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
