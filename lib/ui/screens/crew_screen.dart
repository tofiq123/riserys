import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/crew/crew_service.dart';
import '../../data/nudge/nudge_service.dart';
import '../../domain/crew_member.dart';
import '../../domain/crew_state.dart';
import '../../domain/crew_status.dart';
import '../components/rise_card.dart';
import '../components/section_label.dart';
import '../state/auth_providers.dart';
import '../state/crew_providers.dart';
import '../state/nudge_providers.dart';
import '../state/status_providers.dart';
import '../theme/avatar_color.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'friend_detail_screen.dart';

/// The Crew tab: add friends by username, manage requests, and see your crew.
/// Signed out (or unconfigured) shows a prompt directing to the Profile tab.
class CrewScreen extends ConsumerStatefulWidget {
  const CrewScreen({super.key});

  @override
  ConsumerState<CrewScreen> createState() => _CrewScreenState();
}

class _CrewScreenState extends ConsumerState<CrewScreen> {
  final _query = TextEditingController();
  bool _searching = false;
  bool _busy = false;
  final Set<String> _nudging = {};
  CrewMember? _found;
  String? _searchMessage;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _search() async {
    final q = _query.text.trim();
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

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on FriendshipException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add(CrewMember m) => _run(() async {
        await ref.read(crewServiceProvider).sendRequest(m.id);
        if (!mounted) return;
        _query.clear();
        setState(() {
          _found = null;
          _searchMessage = null;
        });
        _snack('Request sent to @${m.username}.');
      });

  Future<void> _accept(String id) =>
      _run(() => ref.read(crewServiceProvider).acceptRequest(id));
  Future<void> _decline(String id) =>
      _run(() => ref.read(crewServiceProvider).declineRequest(id));
  Future<void> _cancel(String id) =>
      _run(() => ref.read(crewServiceProvider).cancelRequest(id));
  Future<void> _remove(String id) =>
      _run(() => ref.read(crewServiceProvider).removeFriend(id));

  void _openDetail(CrewMember m) {
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => FriendDetailScreen(member: m)));
  }

  Future<void> _nudge(CrewMember m) async {
    if (_nudging.contains(m.id)) return;
    setState(() => _nudging.add(m.id));
    try {
      await ref.read(nudgeServiceProvider).nudge(m.id);
      if (mounted) _snack('Nudged @${m.username} 👋');
    } on NudgeException catch (e) {
      if (mounted) _snack(e.message);
    } catch (_) {
      if (mounted) _snack('Could not send the nudge.');
    } finally {
      if (mounted) setState(() => _nudging.remove(m.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(accountProvider).value;
    if (account == null) return const _CrewSignedOut();

    final crew = ref.watch(crewProvider).value ?? CrewState.empty;
    final statuses =
        ref.watch(crewStatusesProvider).value ?? const <String, CrewStatus>{};

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            RiseSpacing.screen, 8, RiseSpacing.screen, 40),
        children: [
          Text('Crew', style: RiseText.display),
          const SizedBox(height: 6),
          Text('Wake up together. Add friends by username and keep each other honest.',
              style: RiseText.caption),
          const SizedBox(height: 20),
          _addSection(),
          if (crew.incoming.isNotEmpty) ...[
            const SizedBox(height: 24),
            const SectionLabel('Requests'),
            const SizedBox(height: 10),
            for (final m in crew.incoming)
              _memberRow(m, statuses[m.id] ?? CrewStatus.unknown,
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    _pill('Accept', _busy ? null : () => _accept(m.id),
                        filled: true),
                    const SizedBox(width: 6),
                    _pill('Decline', _busy ? null : () => _decline(m.id)),
                  ])),
          ],
          const SizedBox(height: 24),
          const SectionLabel('Your crew'),
          const SizedBox(height: 6),
          _legend(),
          const SizedBox(height: 10),
          if (crew.friends.isEmpty)
            Text('No crew yet. Add friends by username above.',
                style: RiseText.caption)
          else
            for (final m in crew.friends)
              _memberRow(m, statuses[m.id] ?? CrewStatus.unknown,
                  onTap: () => _openDetail(m),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    _pill('Nudge',
                        (_busy || _nudging.contains(m.id))
                            ? null
                            : () => _nudge(m)),
                    const SizedBox(width: 6),
                    _pill('Remove', _busy ? null : () => _remove(m.id),
                        danger: true),
                  ])),
          if (crew.outgoing.isNotEmpty) ...[
            const SizedBox(height: 24),
            const SectionLabel('Pending'),
            const SizedBox(height: 10),
            for (final m in crew.outgoing)
              _memberRow(m, statuses[m.id] ?? CrewStatus.unknown,
                  trailing:
                      _pill('Cancel', _busy ? null : () => _cancel(m.id))),
          ],
        ],
      ),
    );
  }

  Widget _addSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('crew-search-field'),
                controller: _query,
                onSubmitted: (_) => _search(),
                autocorrect: false,
                enableSuggestions: false,
                style: RiseText.body,
                cursorColor: RiseColors.primary,
                decoration: InputDecoration(
                  hintText: 'Add by username',
                  hintStyle:
                      RiseText.body.copyWith(color: RiseColors.textFaint),
                  prefixText: '@',
                  prefixStyle:
                      RiseText.body.copyWith(color: RiseColors.textDim),
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
            _pill('Find', _searching ? null : _search, filled: true),
          ],
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
          _memberRow(_found!, CrewStatus.unknown,
              trailing:
                  _pill('Add', _busy ? null : () => _add(_found!), filled: true)),
        ],
      ],
    );
  }

  Widget _memberRow(CrewMember m, CrewStatus status,
      {required Widget trailing, VoidCallback? onTap}) {
    final card = RiseCard(
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: avatarColorFromHex(m.avatarColor),
                  shape: BoxShape.circle),
              child: Text(
                (m.username.isNotEmpty ? m.username : '?')
                    .characters
                    .first
                    .toUpperCase(),
                style: RiseText.body.copyWith(
                    color: RiseColors.primaryText,
                    fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      m.displayName.isNotEmpty
                          ? m.displayName
                          : '@${m.username}',
                      style:
                          RiseText.body.copyWith(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                  Row(
                    children: [
                      Flexible(
                        child: Text('@${m.username}',
                            style: RiseText.mono(
                                size: 12, color: RiseColors.textDim),
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (status != CrewStatus.unknown) ...[
                        const SizedBox(width: 8),
                        _statusDot(status),
                        const SizedBox(width: 4),
                        Text(_statusLabel(status),
                            style: RiseText.caption.copyWith(
                                fontSize: 11, color: _statusColor(status))),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing,
          ],
        ),
      );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: onTap == null
          ? card
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: card,
            ),
    );
  }

  static Color _statusColor(CrewStatus s) => switch (s) {
        CrewStatus.waking => RiseColors.waking,
        CrewStatus.awake => RiseColors.positive,
        CrewStatus.asleep => RiseColors.asleep,
        CrewStatus.unknown => RiseColors.textFaint,
      };

  static String _statusLabel(CrewStatus s) => switch (s) {
        CrewStatus.waking => 'Waking',
        CrewStatus.awake => 'Awake',
        CrewStatus.asleep => 'Asleep',
        CrewStatus.unknown => '',
      };

  static Widget _statusDot(CrewStatus s) => Container(
        width: 8,
        height: 8,
        decoration:
            BoxDecoration(color: _statusColor(s), shape: BoxShape.circle),
      );

  Widget _legend() => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            for (final s in const [
              CrewStatus.asleep,
              CrewStatus.waking,
              CrewStatus.awake,
            ]) ...[
              _statusDot(s),
              const SizedBox(width: 4),
              Text(_statusLabel(s),
                  style: RiseText.caption
                      .copyWith(fontSize: 11, color: RiseColors.textDim)),
              const SizedBox(width: 12),
            ],
          ],
        ),
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

  static OutlineInputBorder _border(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(RiseRadii.base),
        borderSide: BorderSide(color: color),
      );
}

class _CrewSignedOut extends StatelessWidget {
  const _CrewSignedOut();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.groups_outlined,
                size: 44, color: RiseColors.textFaint),
            const SizedBox(height: 16),
            Text('Wake up with your crew', style: RiseText.title),
            const SizedBox(height: 8),
            Text(
                'Sign in from the Profile tab to add friends and keep each other honest.',
                textAlign: TextAlign.center,
                style: RiseText.body.copyWith(color: RiseColors.textDim)),
          ],
        ),
      ),
    );
  }
}
