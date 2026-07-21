import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/crew/crew_service.dart';
import '../../data/group/group_service.dart';
import '../../domain/crew_member.dart';
import '../../domain/crew_state.dart';
import '../../domain/group.dart';
import '../../domain/premium_feature.dart';
import '../state/crew_providers.dart';
import '../state/entitlement_providers.dart';
import '../state/group_providers.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'crew_avatar.dart';
import 'crew_pill.dart';
import 'crew_sheet.dart';
import 'section_label.dart';
import 'segmented.dart';
import 'toast.dart';

/// Which pane of the add-people sheet to open on.
enum CrewAddMode { friend, joinGroup, newGroup }

/// Opens the add-people sheet: Add friend / Join group / New group in one
/// place, plus your sent (cancellable) friend requests. Resolves to the
/// [Group] that was created or joined (so the caller can push its detail
/// page), or null.
///
/// [onCrewLimit] fires instead of sending a request when the free crew is
/// full and Premium is missing — the caller opens the paywall.
Future<Group?> showCrewAddSheet(
  BuildContext context, {
  CrewAddMode initial = CrewAddMode.friend,
  VoidCallback? onCrewLimit,
}) {
  return showCrewSheet<Group>(
    context,
    builder: (_) => CrewAddSheet(initial: initial, onCrewLimit: onCrewLimit),
  );
}

/// The add-people sheet body. Self-contained (reads the crew/group services
/// via Riverpod) so it can be opened from any crew surface.
class CrewAddSheet extends ConsumerStatefulWidget {
  const CrewAddSheet({super.key, required this.initial, this.onCrewLimit});

  final CrewAddMode initial;
  final VoidCallback? onCrewLimit;

  @override
  ConsumerState<CrewAddSheet> createState() => _CrewAddSheetState();
}

class _CrewAddSheetState extends ConsumerState<CrewAddSheet> {
  late CrewAddMode _mode = widget.initial;
  final _username = TextEditingController();
  final _code = TextEditingController();
  final _name = TextEditingController();
  bool _searching = false;
  bool _busy = false;
  CrewMember? _found;
  String? _searchMessage;

  @override
  void dispose() {
    _username.dispose();
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  void _toast(String message, {RiseToastKind kind = RiseToastKind.info}) {
    if (!mounted) return;
    RiseToast.show(context, message, kind: kind);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on FriendshipException catch (e) {
      _toast(e.message, kind: RiseToastKind.error);
    } on GroupException catch (e) {
      _toast(e.message, kind: RiseToastKind.error);
    } catch (_) {
      _toast('Something went wrong. Try again.', kind: RiseToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---- Add friend ----------------------------------------------------------

  Future<void> _search() async {
    final q = _username.text.trim();
    if (q.isEmpty || _searching) return;
    setState(() {
      _searching = true;
      _found = null;
      _searchMessage = null;
    });
    try {
      final member = await ref.read(crewServiceProvider).findByUsername(q);
      if (!mounted) return;
      setState(() {
        _searching = false;
        _found = member;
        _searchMessage = member == null ? 'No one with the handle "$q".' : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchMessage = 'Could not search right now.';
      });
    }
  }

  Future<void> _add(CrewMember m) {
    // Free crew tops out at [kFreeCrewLimit]; a further add needs Premium. The
    // gate counts accepted friends only (pending requests don't take a seat).
    final gate = ref.read(premiumGateProvider);
    final friendCount =
        (ref.read(crewProvider).value ?? CrewState.empty).friends.length;
    if (!gate.canUse(PremiumFeature.unlimitedCrew) &&
        friendCount >= kFreeCrewLimit) {
      widget.onCrewLimit?.call();
      return Future.value();
    }
    return _run(() async {
      await ref.read(crewServiceProvider).sendRequest(m.id);
      if (!mounted) return;
      _username.clear();
      setState(() {
        _found = null;
        _searchMessage = null;
      });
      _toast('Request sent to @${m.username}.', kind: RiseToastKind.success);
    });
  }

  Future<void> _cancel(String id) =>
      _run(() => ref.read(crewServiceProvider).cancelRequest(id));

  // ---- Groups --------------------------------------------------------------

  Future<void> _join() => _run(() async {
        final code = _code.text.trim();
        if (code.isEmpty) {
          _toast('Enter an invite code.');
          return;
        }
        final group = await ref.read(groupServiceProvider).joinByCode(code);
        ref.invalidate(myGroupsProvider);
        if (!mounted) return;
        _toast('Joined "${group.name}".', kind: RiseToastKind.success);
        Navigator.of(context).pop(group);
      });

  Future<void> _create() => _run(() async {
        final name = _name.text.trim();
        if (name.isEmpty) {
          _toast('Give your group a name first.');
          return;
        }
        final group = await ref.read(groupServiceProvider).createGroup(name);
        ref.invalidate(myGroupsProvider);
        if (!mounted) return;
        Navigator.of(context).pop(group);
      });

  // ---- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final crew = ref.watch(crewProvider).value ?? CrewState.empty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          RiseSpacing.screen, 6, RiseSpacing.screen, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Grow your crew', style: RiseText.title),
          const SizedBox(height: 14),
          SegmentedControl<CrewAddMode>(
            segments: const [
              (value: CrewAddMode.friend, label: 'Add friend'),
              (value: CrewAddMode.joinGroup, label: 'Join group'),
              (value: CrewAddMode.newGroup, label: 'New group'),
            ],
            selected: _mode,
            onChanged: (m) => setState(() => _mode = m),
          ),
          const SizedBox(height: 16),
          switch (_mode) {
            CrewAddMode.friend => _friendPane(crew),
            CrewAddMode.joinGroup => _joinPane(),
            CrewAddMode.newGroup => _createPane(),
          },
        ],
      ),
    );
  }

  Widget _friendPane(CrewState crew) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Ask by handle — they'll get a request to accept.",
            style: RiseText.caption),
        const SizedBox(height: 10),
        _field(
          key: const Key('crew-search-field'),
          controller: _username,
          hint: 'username',
          prefix: '@',
          action: 'Find',
          onSubmit: _searching ? null : _search,
        ),
        if (_searching) ...[
          const SizedBox(height: 10),
          Text('Searching…', style: RiseText.caption),
        ],
        if (_searchMessage != null) ...[
          const SizedBox(height: 10),
          Text(_searchMessage!,
              style: RiseText.caption.copyWith(color: RiseColors.textDim)),
        ],
        if (_found != null) ...[
          const SizedBox(height: 10),
          _memberRow(
            _found!,
            trailing:
                CrewPill('Add', onTap: _busy ? null : () => _add(_found!), filled: true),
          ),
        ],
        if (crew.outgoing.isNotEmpty) ...[
          const SizedBox(height: 18),
          const SectionLabel('Waiting on them'),
          const SizedBox(height: 6),
          for (final m in crew.outgoing)
            _memberRow(
              m,
              trailing:
                  CrewPill('Cancel', onTap: _busy ? null : () => _cancel(m.id)),
            ),
        ],
      ],
    );
  }

  Widget _joinPane() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Enter the invite code your friend shared.',
            style: RiseText.caption),
        const SizedBox(height: 10),
        _field(
          key: const Key('group-code-field'),
          controller: _code,
          hint: 'Invite code',
          action: 'Join',
          onSubmit: _busy ? null : _join,
          uppercase: true,
        ),
      ],
    );
  }

  Widget _createPane() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Name it, then share its invite code with your crew.',
            style: RiseText.caption),
        const SizedBox(height: 10),
        _field(
          key: const Key('group-name-field'),
          controller: _name,
          hint: 'Group name',
          action: 'Create',
          onSubmit: _busy ? null : _create,
        ),
      ],
    );
  }

  Widget _memberRow(CrewMember m, {required Widget trailing}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          CrewAvatar(username: m.username, colorHex: m.avatarColor, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.displayName.isNotEmpty ? m.displayName : '@${m.username}',
                    style: RiseText.body.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text('@${m.username}',
                    style: RiseText.mono(size: 12, color: RiseColors.textDim),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
  }

  Widget _field({
    required Key key,
    required TextEditingController controller,
    required String hint,
    required String action,
    required VoidCallback? onSubmit,
    String? prefix,
    bool uppercase = false,
  }) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            key: key,
            controller: controller,
            onSubmitted: (_) => onSubmit?.call(),
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: uppercase
                ? TextCapitalization.characters
                : TextCapitalization.none,
            style: RiseText.body,
            cursorColor: RiseColors.primary,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: RiseText.body.copyWith(color: RiseColors.textFaint),
              prefixText: prefix,
              prefixStyle: RiseText.body.copyWith(color: RiseColors.textDim),
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
        CrewPill(action, onTap: onSubmit, filled: true),
      ],
    );
  }

  static OutlineInputBorder _border(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(RiseRadii.base),
        borderSide: BorderSide(color: color),
      );
}
