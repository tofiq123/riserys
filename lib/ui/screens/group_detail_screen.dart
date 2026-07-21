import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/group/group_service.dart';
import '../../domain/crew_member.dart';
import '../../domain/crew_score.dart';
import '../../domain/crew_standing.dart';
import '../../domain/group.dart';
import '../components/rise_card.dart';
import '../components/section_label.dart';
import '../components/toast.dart';
import '../state/auth_providers.dart';
import '../state/group_providers.dart';
import '../theme/avatar_color.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// One group's page: its invite code (to share), a group leaderboard reusing the
/// per-member streak/stats data, the roster, and owner/member actions (rename,
/// remove member, leave / delete). Reads via the group providers.
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
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel',
                style: RiseText.body.copyWith(color: RiseColors.textDim)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text('Save',
                style: RiseText.body.copyWith(fontWeight: FontWeight.w600)),
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
        if (mounted) _snack('Removed @${m.username}.', kind: RiseToastKind.success);
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

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(accountProvider).value?.id;
    final board = ref.watch(groupLeaderboardProvider(_gid));
    final members = ref.watch(groupMembersProvider(_gid));

    return Scaffold(
      backgroundColor: RiseColors.appBg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              RiseSpacing.screen, 8, RiseSpacing.screen, 40),
          children: [
            _header(),
            const SizedBox(height: 20),
            _inviteCard(),
            const SizedBox(height: 24),
            const SectionLabel('Group leaderboard'),
            const SizedBox(height: 12),
            board.when(
              data: (standings) => standings.isEmpty
                  ? Text('No streaks yet — start waking up together.',
                      style: RiseText.caption)
                  : Column(children: [
                      _scoreCard(computeCrewScore(standings)),
                      const SizedBox(height: 14),
                      for (var i = 0; i < standings.length; i++)
                        _standingRow(i + 1, standings[i]),
                    ]),
              loading: _spinner,
              error: (_, __) => Text('Could not load the leaderboard.',
                  style: RiseText.caption),
            ),
            const SizedBox(height: 24),
            const SectionLabel('Members'),
            const SizedBox(height: 12),
            members.when(
              data: (list) => list.isEmpty
                  ? Text('No members to show yet.', style: RiseText.caption)
                  : Column(
                      children: [for (final m in list) _memberRow(m, me)]),
              loading: _spinner,
              error: (_, __) =>
                  Text('Could not load members.', style: RiseText.caption),
            ),
            const SizedBox(height: 28),
            _footerAction(),
          ],
        ),
      ),
    );
  }

  Widget _spinner() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );

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
            child: Text(_group.name,
                style: RiseText.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          if (_group.isOwner)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _busy ? null : _rename,
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.edit_outlined,
                    color: RiseColors.textDim, size: 20),
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
                      style: RiseText.caption
                          .copyWith(color: RiseColors.textDim)),
                  const SizedBox(height: 4),
                  Text(_group.inviteCode,
                      style: RiseText.mono(size: 24, weight: FontWeight.w600),
                      maxLines: 1),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _pill('Copy', _copyCode, filled: true),
          ],
        ),
      );

  Widget _scoreCard(CrewScore score) {
    final you = score.you;
    final sub = you == null
        ? '${score.memberCount} climbing together.'
        : 'Your part: ${you.points} pts · ${you.sharePercent}% of the group.';
    return Container(
      padding: const EdgeInsets.all(RiseSpacing.screen),
      decoration: BoxDecoration(
        color: RiseColors.primary,
        borderRadius: BorderRadius.circular(RiseRadii.base),
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
        ],
      ),
    );
  }

  Widget _standingRow(int rank, CrewStanding s) {
    final onTimePct = (s.stats.onTimeRate * 100).round();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(RiseSpacing.cardPad),
        decoration: BoxDecoration(
          color: s.isMe ? RiseColors.accentSoft : RiseColors.card,
          borderRadius: BorderRadius.circular(RiseRadii.base),
          border:
              Border.all(color: s.isMe ? RiseColors.accent : RiseColors.border),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: Text('$rank',
                  style: RiseText.mono(size: 15, weight: FontWeight.w600)),
            ),
            const SizedBox(width: 8),
            _avatar(s.username, s.avatarColor, 34),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.displayName.isNotEmpty ? s.displayName : '@${s.username}',
                      style:
                          RiseText.body.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text('@${s.username} · $onTimePct% on time',
                      style: RiseText.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${s.stats.currentStreak}',
                    style: RiseText.mono(size: 18, weight: FontWeight.w600)),
                Text('day streak',
                    style: RiseText.caption.copyWith(fontSize: 10)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _memberRow(CrewMember m, String? me) {
    final isOwner = m.id == _group.ownerId;
    final isSelf = m.id == me;
    final canRemove = _group.isOwner && !isSelf;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RiseCard(
        child: Row(
          children: [
            _avatar(m.username, m.avatarColor, 38),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.displayName.isNotEmpty ? m.displayName : '@${m.username}',
                      style:
                          RiseText.body.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text('@${m.username}',
                      style: RiseText.mono(size: 12, color: RiseColors.textDim),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (isOwner) ...[
              const SizedBox(width: 8),
              _badge('Owner'),
            ],
            if (canRemove) ...[
              const SizedBox(width: 8),
              _pill('Remove', _busy ? null : () => _removeMember(m),
                  danger: true),
            ],
          ],
        ),
      ),
    );
  }

  Widget _footerAction() => _group.isOwner
      ? _wideButton('Delete group', _busy ? null : _delete, danger: true)
      : _wideButton('Leave group', _busy ? null : _leave, danger: true);

  Widget _avatar(String username, String colorHex, double size) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: avatarColorFromHex(colorHex), shape: BoxShape.circle),
        child: Text(
          (username.isNotEmpty ? username : '?').characters.first.toUpperCase(),
          style: RiseText.body.copyWith(
              color: RiseColors.primaryText, fontWeight: FontWeight.w700),
        ),
      );

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

  Widget _pill(String label, VoidCallback? onTap,
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(RiseRadii.sm),
            border: filled ? null : Border.all(color: RiseColors.border),
          ),
          child: Text(label,
              style: RiseText.body.copyWith(
                  color: fg, fontWeight: FontWeight.w600, fontSize: 13)),
        ),
      ),
    );
  }

  Widget _wideButton(String label, VoidCallback? onTap, {bool danger = false}) {
    return Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: RiseColors.card,
            borderRadius: BorderRadius.circular(RiseRadii.sm),
            border: Border.all(
                color: danger ? RiseColors.danger : RiseColors.border),
          ),
          child: Text(label,
              style: RiseText.body.copyWith(
                  color: danger ? RiseColors.danger : RiseColors.text,
                  fontWeight: FontWeight.w600,
                  fontSize: 14)),
        ),
      ),
    );
  }
}
