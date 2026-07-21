import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/group/group_service.dart';
import '../../domain/group.dart';
import '../components/rise_card.dart';
import '../components/section_label.dart';
import '../components/toast.dart';
import '../state/group_providers.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'group_detail_screen.dart';

/// The Groups sub-view of the Crew tab: create a group, join by invite code, and
/// see the groups you're in. Rendered as a plain [Column] so it embeds in the
/// Crew screen's scroll (no nested scroll view). Deep-link invites and
/// challenges are deferred to a later phase.
class GroupsTab extends ConsumerStatefulWidget {
  const GroupsTab({super.key});

  @override
  ConsumerState<GroupsTab> createState() => _GroupsTabState();
}

class _GroupsTabState extends ConsumerState<GroupsTab> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  void _snack(String message, {RiseToastKind kind = RiseToastKind.info}) {
    if (!mounted) return;
    RiseToast.show(context, message, kind: kind);
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

  Future<void> _create() => _run(() async {
        final name = _name.text.trim();
        if (name.isEmpty) {
          _snack('Give your group a name first.', kind: RiseToastKind.info);
          return;
        }
        final group = await ref.read(groupServiceProvider).createGroup(name);
        ref.invalidate(myGroupsProvider);
        if (!mounted) return;
        _name.clear();
        _open(group);
      });

  Future<void> _join() => _run(() async {
        final code = _code.text.trim();
        if (code.isEmpty) {
          _snack('Enter an invite code.', kind: RiseToastKind.info);
          return;
        }
        final group = await ref.read(groupServiceProvider).joinByCode(code);
        ref.invalidate(myGroupsProvider);
        if (!mounted) return;
        _code.clear();
        _snack('Joined "${group.name}".', kind: RiseToastKind.success);
        _open(group);
      });

  void _open(Group g) {
    Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => GroupDetailScreen(group: g)));
  }

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(myGroupsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field(
          key: const Key('group-name-field'),
          controller: _name,
          hint: 'Name a new group',
          action: 'Create',
          onSubmit: _create,
        ),
        const SizedBox(height: 12),
        _field(
          key: const Key('group-code-field'),
          controller: _code,
          hint: 'Join with an invite code',
          action: 'Join',
          onSubmit: _join,
          uppercase: true,
        ),
        const SizedBox(height: 24),
        const SectionLabel('Your groups'),
        const SizedBox(height: 10),
        groups.when(
          data: (list) => list.isEmpty
              ? Text(
                  'No groups yet. Start one and share the code, or join a '
                  'friend\'s with theirs.',
                  style: RiseText.caption)
              : Column(children: [for (final g in list) _groupRow(g)]),
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          ),
          error: (_, __) => Row(
            children: [
              Expanded(
                child: Text('Could not load your groups.',
                    style: RiseText.caption),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => ref.invalidate(myGroupsProvider),
                child: Text('Retry',
                    style: RiseText.caption.copyWith(
                        color: RiseColors.accent, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _field({
    required Key key,
    required TextEditingController controller,
    required String hint,
    required String action,
    required VoidCallback onSubmit,
    bool uppercase = false,
  }) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            key: key,
            controller: controller,
            onSubmitted: (_) => onSubmit(),
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: uppercase
                ? TextCapitalization.characters
                : TextCapitalization.sentences,
            style: RiseText.body,
            cursorColor: RiseColors.primary,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: RiseText.body.copyWith(color: RiseColors.textFaint),
              filled: true,
              fillColor: RiseColors.surface2,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: _border(RiseColors.border),
              enabledBorder: _border(RiseColors.border),
              focusedBorder: _border(RiseColors.primary),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _pill(action, _busy ? null : onSubmit, filled: true),
      ],
    );
  }

  Widget _groupRow(Group g) {
    final subtitle = g.isOwner ? 'You own this' : 'Member';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _open(g),
        child: RiseCard(
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: RiseColors.accentSoft,
                  borderRadius: BorderRadius.circular(RiseRadii.sm),
                  border: Border.all(color: RiseColors.border),
                ),
                child: Icon(Icons.groups_outlined,
                    size: 22, color: RiseColors.textDim),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(g.name,
                        style:
                            RiseText.body.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text(subtitle,
                        style: RiseText.caption, maxLines: 1),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  size: 20, color: RiseColors.textFaint),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(String label, VoidCallback? onTap, {bool filled = false}) {
    final bg = filled ? RiseColors.primary : RiseColors.card;
    final fg = filled ? RiseColors.primaryText : RiseColors.text;
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

  static OutlineInputBorder _border(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(RiseRadii.base),
        borderSide: BorderSide(color: color),
      );
}
