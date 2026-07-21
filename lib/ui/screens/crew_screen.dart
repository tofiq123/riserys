import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/crew/crew_service.dart';
import '../../data/nudge/nudge_service.dart';
import '../../domain/crew_member.dart';
import '../../domain/crew_state.dart';
import '../../domain/crew_status.dart';
import '../../domain/premium_feature.dart';
import '../components/confirm_dialog.dart';
import '../components/rise_card.dart';
import '../components/section_label.dart';
import '../components/segmented.dart';
import '../components/toast.dart';
import '../state/auth_providers.dart';
import '../state/crew_providers.dart';
import '../state/entitlement_providers.dart';
import '../state/nudge_providers.dart';
import '../state/status_providers.dart';
import '../state/voice_providers.dart';
import '../theme/avatar_color.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'activity_feed_screen.dart';
import 'friend_detail_screen.dart';
import 'groups_tab.dart';
import 'paywall_screen.dart';
import 'voice_inbox_screen.dart';

/// The two sub-views of the Crew tab.
enum _CrewView { friends, groups }

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
  _CrewView _view = _CrewView.friends;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _snack(String message, {RiseToastKind kind = RiseToastKind.info}) {
    if (!mounted) return;
    RiseToast.show(context, message, kind: kind);
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
      _snack(e.message, kind: RiseToastKind.error);
    } catch (_) {
      _snack('Something went wrong. Try again.', kind: RiseToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add(CrewMember m) {
    // Free crew tops out at [kFreeCrewLimit]; a further add needs Premium. The
    // gate counts accepted friends only (pending requests don't consume a seat).
    // Unconfigured/unlocked → canUse is true, so there's no limit.
    final gate = ref.read(premiumGateProvider);
    final friendCount =
        (ref.read(crewProvider).value ?? CrewState.empty).friends.length;
    if (!gate.canUse(PremiumFeature.unlimitedCrew) &&
        friendCount >= kFreeCrewLimit) {
      openPaywall(context);
      return Future.value();
    }
    return _run(() async {
      await ref.read(crewServiceProvider).sendRequest(m.id);
      if (!mounted) return;
      _query.clear();
      setState(() {
        _found = null;
        _searchMessage = null;
      });
      _snack('Request sent to @${m.username}.', kind: RiseToastKind.success);
    });
  }

  Future<void> _accept(String id) =>
      _run(() => ref.read(crewServiceProvider).acceptRequest(id));
  Future<void> _decline(String id) =>
      _run(() => ref.read(crewServiceProvider).declineRequest(id));
  Future<void> _cancel(String id) =>
      _run(() => ref.read(crewServiceProvider).cancelRequest(id));
  Future<void> _remove(CrewMember m) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Remove @${m.username}?',
      message: "You'll stop seeing each other's wake status and streaks. "
          'You can add them back anytime.',
      confirmLabel: 'Remove',
      danger: true,
    );
    if (!ok) return;
    await _run(() => ref.read(crewServiceProvider).removeFriend(m.id));
  }

  void _openDetail(CrewMember m) {
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => FriendDetailScreen(member: m)));
  }

  Future<void> _nudge(CrewMember m) async {
    if (_nudging.contains(m.id)) return;
    setState(() => _nudging.add(m.id));
    try {
      await ref.read(nudgeServiceProvider).nudge(m.id);
      if (mounted) _snack('Nudged @${m.username} 👋', kind: RiseToastKind.success);
    } on NudgeException catch (e) {
      if (mounted) _snack(e.message, kind: RiseToastKind.error);
    } catch (_) {
      if (mounted) _snack('Could not send the nudge.', kind: RiseToastKind.error);
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
          Text('Wake up together. Add friends, form groups, and keep each other honest.',
              style: RiseText.caption),
          const SizedBox(height: 16),
          SegmentedControl<_CrewView>(
            segments: const [
              (value: _CrewView.friends, label: 'Friends'),
              (value: _CrewView.groups, label: 'Groups'),
            ],
            selected: _view,
            onChanged: (v) => setState(() => _view = v),
          ),
          const SizedBox(height: 20),
          if (_view == _CrewView.groups)
            const GroupsTab()
          else ...[
            _activityFeedTile(),
            const SizedBox(height: 12),
            _voiceInboxTile(),
            const SizedBox(height: 16),
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
                      _pill('Remove', _busy ? null : () => _remove(m),
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
        ],
      ),
    );
  }

  Widget _activityFeedTile() {
    return GestureDetector(
      key: const Key('activity-feed-tile'),
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const ActivityFeedScreen())),
      child: RiseCard(
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: RiseColors.accentSoft, shape: BoxShape.circle),
              child: Icon(Icons.wb_sunny_outlined,
                  color: RiseColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Activity',
                      style:
                          RiseText.body.copyWith(fontWeight: FontWeight.w600)),
                  Text('Crew wake-ups — cheer each other on',
                      style: RiseText.caption),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: RiseColors.textFaint),
          ],
        ),
      ),
    );
  }

  Widget _voiceInboxTile() {
    final clips = ref.watch(voiceInboxProvider).value ?? const [];
    final unread = clips.where((c) => !c.isPlayed).length;
    return GestureDetector(
      key: const Key('voice-inbox-tile'),
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const VoiceInboxScreen())),
      child: RiseCard(
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: RiseColors.accentSoft, shape: BoxShape.circle),
              child: Icon(Icons.graphic_eq,
                  color: RiseColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Voice inbox',
                      style:
                          RiseText.body.copyWith(fontWeight: FontWeight.w600)),
                  Text(
                      unread > 0
                          ? '$unread new ${unread == 1 ? 'clip' : 'clips'}'
                          : 'Voice clips from your crew',
                      style: RiseText.caption),
                ],
              ),
            ),
            if (unread > 0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: RiseColors.primary,
                    borderRadius: BorderRadius.circular(RiseRadii.pill)),
                child: Text('$unread',
                    style: RiseText.mono(
                        size: 12,
                        weight: FontWeight.w600,
                        color: RiseColors.primaryText)),
              ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, color: RiseColors.textFaint),
          ],
        ),
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
            Icon(Icons.groups_outlined,
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
