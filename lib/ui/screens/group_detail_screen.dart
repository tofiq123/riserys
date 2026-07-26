import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/group/group_service.dart';
import '../../data/invite_links.dart';
import '../../domain/crew_member.dart';
import '../../domain/crew_score.dart';
import '../../domain/crew_standing.dart';
import '../../domain/crew_status.dart';
import '../../domain/group.dart';
import '../../domain/group_challenge.dart';
import '../../domain/group_roster.dart';
import '../components/crew_avatar.dart';
import '../components/crew_entrance.dart';
import '../components/crew_pill.dart';
import '../components/crew_sheet.dart';
import '../components/hero_card.dart';
import '../components/podium.dart';
import '../components/rise_buttons.dart';
import '../components/rise_card.dart';
import '../components/rise_motion.dart';
import '../components/rise_skeleton.dart';
import '../components/section_label.dart';
import '../components/toast.dart';
import '../state/auth_providers.dart';
import '../state/group_providers.dart';
import '../state/status_providers.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'friend_detail_screen.dart';

/// One group's page, ordered by what you came for.
///
/// It used to open on the invite code — the thing you need once. It now opens
/// on the group's morning, then the race, then the standings, and the invite
/// sits near the end where you go looking for it deliberately.
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
        text:
            'Join my Riserys group "${_group.name}" — we wake up together.\n$link',
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

  void _openMember(CrewMember m) {
    Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => FriendDetailScreen(member: m)));
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(accountProvider).valueOrNull?.id;
    final board = ref.watch(groupLeaderboardProvider(_gid));
    final members = ref.watch(groupMembersProvider(_gid));
    final challengeAsync = ref.watch(groupChallengeProvider(_gid));
    final challenge = challengeAsync.valueOrNull;
    final statuses =
        ref.watch(crewStatusesProvider).valueOrNull ?? const <String, CrewStatus>{};

    final standings = board.valueOrNull ?? const <CrewStanding>[];
    // First load (nothing cached yet) → skeletons; afterwards data renders even
    // while a refresh is in flight.
    final loading = (board.isLoading && !board.hasValue) ||
        (members.isLoading && !members.hasValue);
    final failed = board.hasError && members.hasError;
    final roster = mergeRoster(standings, members.valueOrNull ?? const []);
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
    final solo = roster.length <= 1 && !loading;

    return Scaffold(
      backgroundColor: RiseColors.appBg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              RiseSpacing.screen, 8, RiseSpacing.screen, 40),
          children: [
            CrewEntrance(index: 0, child: _header(roster.length)),
            const SizedBox(height: 14),
            if (loading) ...[
              const RiseSkeleton(height: 148, radius: RiseRadii.lg),
              const SizedBox(height: 26),
              const _RosterSkeleton(),
            ] else if (failed) ...[
              const SizedBox(height: 24),
              Text('Could not load this group.', style: RiseText.caption),
            ] else if (solo) ...[
              CrewEntrance(index: 1, child: _soloHero(me)),
              const SizedBox(height: 22),
              CrewEntrance(index: 2, child: _inviteCard(prominent: true)),
            ] else ...[
              CrewEntrance(
                index: 1,
                child: _morningHero(roster, statuses),
              ),
              const SizedBox(height: 16),
              CrewEntrance(
                index: 2,
                child: _raceSection(challenge, standings, challengeAsync),
              ),
              const SizedBox(height: 26),
              CrewEntrance(
                index: 3,
                child: _standingsSection(roster, me, race: race),
              ),
              if (standings.isNotEmpty) ...[
                const SizedBox(height: 26),
                CrewEntrance(
                    index: 4, child: _scoreCard(computeCrewScore(standings))),
              ],
              const SizedBox(height: 26),
              CrewEntrance(
                index: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionLabel('Invite'),
                    const SizedBox(height: 12),
                    _inviteCard(),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 30),
            CrewEntrance(index: 6, child: _footerAction()),
          ],
        ),
      ),
    );
  }

  Widget _header(int memberCount) => Row(
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_group.name,
                    style: RiseText.title.copyWith(fontSize: 19),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 1),
                Text(
                    '${memberCount == 0 ? "" : "$memberCount "}'
                    '${memberCount == 1 ? "member" : "members"} · '
                    '${_group.isOwner ? "you own this group" : "you're a member"}',
                    style: RiseText.caption.copyWith(fontSize: 11.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
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

  /// The group's morning, in the same vocabulary as the Crew tab — a group is a
  /// crew, so it should read like one.
  Widget _morningHero(List<RosterEntry> roster, Map<String, CrewStatus> statuses) {
    final up = roster
        .where((e) =>
            statuses[e.member.id] == CrewStatus.awake ||
            statuses[e.member.id] == CrewStatus.out)
        .length;
    return HeroCard(
      key: const Key('group-morning-hero'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                    shape: BoxShape.circle, color: RiseColors.waking),
              ),
              const SizedBox(width: 7),
              Text('THIS MORNING',
                  style: RiseText.sectionLabel
                      .copyWith(color: RiseColors.primaryText)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: RiseCountUp(
                  value: up,
                  style: RiseText.mono(
                      size: 36,
                      weight: FontWeight.w600,
                      color: RiseColors.primaryText,
                      letterSpacing: -1.2),
                ),
              ),
              const SizedBox(width: 9),
              Flexible(
                child: Opacity(
                  opacity: 0.8,
                  child: Text('of ${roster.length} up',
                      style: RiseText.body.copyWith(
                          color: RiseColors.primaryText, fontSize: 15),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.fade),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: roster.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) {
                final m = roster[i].member;
                final status = statuses[m.id] ?? CrewStatus.unknown;
                return Center(
                  child: CrewAvatar(
                    username: m.username,
                    colorHex: m.avatarColor,
                    size: 30,
                    ring: status == CrewStatus.unknown ? null : status,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// A group of one is the most common first state, and it used to render as an
  /// empty leaderboard. It is a share screen instead.
  Widget _soloHero(String? me) => HeroCard(
        key: const Key('group-solo-hero'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.groups_outlined, size: 28, color: RiseColors.waking),
            const SizedBox(height: 14),
            Text('A group of one is a good start.',
                style: RiseText.title
                    .copyWith(fontSize: 20, color: RiseColors.primaryText)),
            const SizedBox(height: 8),
            Opacity(
              opacity: 0.75,
              child: Text(
                  'Share the code and their mornings show up here, next to '
                  'yours.',
                  style: RiseText.body.copyWith(
                      color: RiseColors.primaryText, height: 1.4)),
            ),
          ],
        ),
      );

  /// The race, as a banner in its own right rather than a line inside a card.
  Widget _raceSection(GroupChallenge? challenge, List<CrewStanding> standings,
      AsyncValue<GroupChallenge?> challengeAsync) {
    final c = challenge;
    if (c != null && c.isActive) {
      final now = DateTime.now();
      final day = challengeDayCount(startedAt: c.startedAt, now: now);
      final rows = challengeStandings(
          startedAt: c.startedAt, now: now, standings: standings);
      final alive = rows.where((r) => r.inRace).length;
      return Container(
        key: const Key('group-race-banner'),
        padding: const EdgeInsets.all(RiseSpacing.cardPad),
        decoration: BoxDecoration(
          color: RiseColors.card,
          borderRadius: BorderRadius.circular(RiseRadii.base),
          border: Border.all(color: RiseColors.waking),
          boxShadow: RiseShadows.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('🔥', style: TextStyle(fontSize: 15)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Streak race · day $day',
                      style:
                          RiseText.body.copyWith(fontWeight: FontWeight.w600)),
                ),
                if (_group.isOwner)
                  GestureDetector(
                    key: const Key('end-race-action'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _busy ? null : () => _endRace(c),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 6),
                      child: Text('End race',
                          style: RiseText.caption.copyWith(
                              color: RiseColors.textDim,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
                '$alive still standing of ${rows.length}. '
                'Ends when one is left.',
                style: RiseText.caption),
            if (rows.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  for (final r in rows)
                    Padding(
                      padding: const EdgeInsets.only(right: 5),
                      child: Container(
                        width: 20,
                        height: 4,
                        decoration: BoxDecoration(
                          color: r.inRace
                              ? RiseColors.waking
                              : RiseColors.border,
                          borderRadius: BorderRadius.circular(RiseRadii.pill),
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

    // No race. Only offer the CTA once we know there genuinely isn't one.
    if (!challengeAsync.hasValue) return const SizedBox.shrink();
    if (!_group.isOwner) {
      return RiseCard(
        radius: RiseRadii.base,
        child: Row(
          children: [
            const Text('🔥', style: TextStyle(fontSize: 15)),
            const SizedBox(width: 10),
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
      radius: RiseRadii.base,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              'Everyone keeps their streak alive — last one standing wins. '
              'Kind, not cut-throat.',
              style: RiseText.caption),
          const SizedBox(height: 12),
          PrimaryButton(
            label: 'Start a streak race',
            onPressed: _busy ? null : _startRace,
          ),
        ],
      ),
    );
  }

  Widget _standingsSection(List<RosterEntry> roster, String? me,
      {required Map<String, bool>? race}) {
    // Only ranked entries can stand on a podium; unranked members (no wakes
    // yet) always read as rows, never as an empty plinth.
    final ranked = [
      for (final e in roster)
        if (e.standing != null) e.standing!
    ];
    final podium = ranked.take(3).toList();
    final rest = [
      for (var i = 0; i < roster.length; i++)
        if (roster[i].standing == null ||
            !podium.contains(roster[i].standing))
          (index: i, entry: roster[i])
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SectionLabel('Standings'),
            const Spacer(),
            Text('by run',
                style: RiseText.caption.copyWith(fontSize: 11.5)),
          ],
        ),
        const SizedBox(height: 14),
        if (podium.isNotEmpty) ...[
          Podium(
            top: podium,
            onTap: (s) => _openMember(_memberFor(roster, s)),
          ),
          const SizedBox(height: 18),
        ],
        if (roster.isEmpty)
          Text('No members to show yet.', style: RiseText.caption)
        else
          for (final r in rest)
            _memberRow(r.entry, me, rank: r.index + 1, race: race),
      ],
    );
  }

  CrewMember _memberFor(List<RosterEntry> roster, CrewStanding s) =>
      roster
          .firstWhere((e) => e.member.id == s.id,
              orElse: () => RosterEntry(
                  member: CrewMember(
                      id: s.id,
                      username: s.username,
                      displayName: s.displayName,
                      avatarColor: s.avatarColor),
                  standing: s,
                  rank: null))
          .member;

  Widget _scoreCard(CrewScore score) {
    final you = score.you;
    return HeroCard(
      eyebrow: 'TOGETHER',
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: RiseCountUp(
                  value: score.crewTotal,
                  style: RiseText.mono(
                      size: 34,
                      weight: FontWeight.w600,
                      color: RiseColors.primaryText,
                      letterSpacing: -1),
                ),
              ),
              const SizedBox(width: 9),
              Flexible(
                child: Opacity(
                  opacity: 0.75,
                  child: Text('group score',
                      style: RiseText.body.copyWith(
                          color: RiseColors.primaryText, fontSize: 14),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.fade),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Opacity(
            opacity: 0.75,
            child: Text(
                you == null
                    ? '${score.memberCount} climbing together.'
                    : 'Your part: ${you.points} pts · ${you.sharePercent}% of '
                        'the group.',
                style:
                    RiseText.caption.copyWith(color: RiseColors.primaryText)),
          ),
        ],
      ),
    );
  }

  Widget _inviteCard({bool prominent = false}) => RiseCard(
        padding: const EdgeInsets.all(RiseSpacing.screen),
        child: prominent
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Invite code', style: RiseText.caption),
                  const SizedBox(height: 6),
                  Text(_group.inviteCode,
                      style: RiseText.mono(
                          size: 28,
                          weight: FontWeight.w600,
                          letterSpacing: 3),
                      maxLines: 1),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      CrewPill('Share link', onTap: _shareLink, filled: true),
                      const SizedBox(width: 8),
                      CrewPill('Copy', onTap: _copyCode, filled: false),
                    ],
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Invite code', style: RiseText.caption),
                        const SizedBox(height: 4),
                        Text(_group.inviteCode,
                            style: RiseText.mono(
                                size: 22,
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

  /// One merged member row: rank, avatar, identity, race chip (when a race
  /// runs), streak — and the owner's remove action behind a per-row overflow.
  /// Every person on this page appears exactly once, here or on the podium.
  Widget _memberRow(RosterEntry entry, String? me,
      {required int rank, required Map<String, bool>? race}) {
    final m = entry.member;
    final s = entry.standing;
    final isOwner = m.id == _group.ownerId;
    final isSelf = m.id == me || (s?.isMe ?? false);
    final canRemove = _group.isOwner && !isSelf;
    final onTimePct = s == null ? null : (s.stats.onTimeRate * 100).round();
    final inRace = race?[m.id];

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RisePressable(
        key: Key('group-row-${m.username}'),
        onTap: isSelf ? null : () => _openMember(m),
        child: Container(
          padding: const EdgeInsets.all(RiseSpacing.cardPad),
          decoration: BoxDecoration(
            color: isSelf ? RiseColors.accentSoft : RiseColors.card,
            borderRadius: BorderRadius.circular(RiseRadii.base),
            border: Border.all(
                color: isSelf ? RiseColors.accent : RiseColors.border),
            boxShadow: RiseShadows.card,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                child: Text(entry.rank == null ? '·' : '$rank',
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
                Text(inRace ? '🔥' : '💤', style: const TextStyle(fontSize: 15)),
              ],
              if (s != null) ...[
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${s.stats.currentStreak}',
                        style: RiseText.mono(size: 18, weight: FontWeight.w600)),
                    Text('day run',
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

/// The roster's loading shape: the podium's silhouette, then rows. The header
/// is real immediately — the group you tapped supplied its name.
class _RosterSkeleton extends StatelessWidget {
  const _RosterSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Standings'),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final h in [90.0, 104.0, 80.0])
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.5),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RiseSkeletonCircle(size: h == 104.0 ? 44 : 36),
                    const SizedBox(height: 9),
                    RiseSkeleton(width: 96, height: h, radius: RiseRadii.base),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 18),
        for (var i = 0; i < 2; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: RiseCard(
              radius: RiseRadii.base,
              child: Row(
                children: [
                  const SizedBox(width: 30),
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
          ),
      ],
    );
  }
}
