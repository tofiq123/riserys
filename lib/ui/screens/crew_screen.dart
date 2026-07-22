import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/auth/auth_service.dart';
import '../../domain/crew_member.dart';
import '../../domain/crew_state.dart';
import '../../domain/crew_status.dart';
import '../../domain/feed_item.dart';
import '../components/crew_add_sheet.dart';
import '../components/crew_avatar.dart';
import '../components/crew_entrance.dart';
import '../components/crew_feed_tile.dart';
import '../components/crew_hero.dart';
import '../components/crew_member_chip.dart';
import '../components/crew_requests_sheet.dart';
import '../components/rise_buttons.dart';
import '../components/rise_card.dart';
import '../components/rise_error_card.dart';
import '../components/rise_spinner.dart';
import '../components/section_label.dart';
import '../components/toast.dart';
import '../state/auth_providers.dart';
import '../state/crew_providers.dart';
import '../state/feed_providers.dart';
import '../state/status_providers.dart';
import '../state/voice_providers.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'activity_feed_screen.dart';
import 'friend_detail_screen.dart';
import 'group_detail_screen.dart';
import 'groups_tab.dart';
import 'paywall_screen.dart';
import 'voice_inbox_screen.dart';

/// The Crew tab — a mornings-together dashboard, not an address book.
///
/// Top to bottom: header (title + voice-inbox and add-people icon actions,
/// each with a live badge), a requests banner when someone is waiting, the
/// This-morning strip of live member chips, the inline "Cheer them on" feed,
/// and the Groups strip. Adding friends, joining and creating groups all live
/// in one bottom sheet behind the `+` action.
///
/// Signed out (or an unconfigured backend) shows a warm hero instead — the
/// whole app stays usable without an account.
class CrewScreen extends ConsumerStatefulWidget {
  const CrewScreen({super.key});

  @override
  ConsumerState<CrewScreen> createState() => _CrewScreenState();
}

class _CrewScreenState extends ConsumerState<CrewScreen> {
  void _push(Widget screen) {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  Future<void> _openAddSheet(
      [CrewAddMode mode = CrewAddMode.friend]) async {
    final group = await showCrewAddSheet(
      context,
      initial: mode,
      onCrewLimit: () => openPaywall(context),
    );
    if (group != null && mounted) _push(GroupDetailScreen(group: group));
  }

  void _openDetail(CrewMember m) => _push(FriendDetailScreen(member: m));

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(accountProvider).value;
    if (account == null) {
      final configured =
          ref.watch(authServiceProvider) is! DisabledAuthService;
      return _CrewSignedOut(configured: configured);
    }

    final crew = ref.watch(crewProvider).value ?? CrewState.empty;
    final statuses =
        ref.watch(crewStatusesProvider).value ?? const <String, CrewStatus>{};
    final feed = ref.watch(crewFeedProvider);
    final hasCrew = crew.friends.isNotEmpty;
    // With no crew the hero carries the screen; the feed section only stays
    // if there is genuinely something to cheer (e.g. your own wakes).
    final showFeed = hasCrew || (feed.value?.isNotEmpty ?? false);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            RiseSpacing.screen, 8, RiseSpacing.screen, 40),
        children: [
          CrewEntrance(index: 0, child: _header(crew)),
          const SizedBox(height: 20),
          if (crew.incoming.isNotEmpty) ...[
            CrewEntrance(index: 1, child: _requestsBanner(crew.incoming)),
            const SizedBox(height: 20),
          ],
          if (hasCrew) ...[
            CrewEntrance(index: 2, child: _morningStrip(crew, statuses)),
            const SizedBox(height: 26),
          ] else ...[
            CrewEntrance(index: 2, child: _emptyCrewHero()),
            const SizedBox(height: 26),
          ],
          if (showFeed) ...[
            CrewEntrance(index: 3, child: _feedSection(feed)),
            const SizedBox(height: 26),
          ],
          CrewEntrance(index: 4, child: _groupsSection()),
        ],
      ),
    );
  }

  // ---- Header --------------------------------------------------------------

  Widget _header(CrewState crew) {
    final clips = ref.watch(voiceInboxProvider).value ?? const [];
    final unread = clips.where((c) => !c.isPlayed).length;
    return Row(
      children: [
        Text('Crew', style: RiseText.display),
        const Spacer(),
        _HeaderIcon(
          key: const Key('crew-voice-inbox'),
          icon: Icons.graphic_eq,
          badge: unread,
          semanticLabel: 'Voice inbox',
          onTap: () => _push(const VoiceInboxScreen()),
        ),
        const SizedBox(width: 10),
        _HeaderIcon(
          key: const Key('crew-add-button'),
          icon: Icons.add,
          badge: crew.incoming.length,
          semanticLabel: 'Add people',
          onTap: _openAddSheet,
        ),
      ],
    );
  }

  // ---- Requests banner -----------------------------------------------------

  Widget _requestsBanner(List<CrewMember> incoming) {
    final first = incoming.first;
    final name =
        first.displayName.isNotEmpty ? first.displayName : '@${first.username}';
    final title = incoming.length == 1
        ? '$name wants to join your crew'
        : '${incoming.length} people want to join your crew';
    return GestureDetector(
      key: const Key('crew-requests-banner'),
      behavior: HitTestBehavior.opaque,
      onTap: () => showCrewRequestsSheet(context),
      child: RiseCard(
        child: Row(
          children: [
            SizedBox(
              width: incoming.length > 1 ? 54 : 40,
              height: 40,
              child: Stack(
                children: [
                  for (var i = 0;
                      i < (incoming.length > 1 ? 2 : 1);
                      i++)
                    Positioned(
                      left: i * 14.0,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: RiseColors.card, width: 2),
                        ),
                        child: CrewAvatar(
                          username: incoming[i].username,
                          colorHex: incoming[i].avatarColor,
                          size: 36,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style:
                          RiseText.body.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text('Tap to accept or decline', style: RiseText.caption),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: RiseColors.textFaint),
          ],
        ),
      ),
    );
  }

  // ---- This morning --------------------------------------------------------

  Widget _morningStrip(CrewState crew, Map<String, CrewStatus> statuses) {
    final members = sortMembersByStatus(crew.friends, statuses);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('This morning'),
        const SizedBox(height: 12),
        SizedBox(
          height: 104,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: members.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) => CrewMemberChip(
              member: members[i],
              status: statuses[members[i].id] ?? CrewStatus.unknown,
              onTap: () => _openDetail(members[i]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _emptyCrewHero() {
    return RiseCard(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
      child: CrewHero(
        icon: Icons.wb_twilight,
        title: 'Mornings are better with a crew',
        body: 'Add a friend to see each other wake up, keep streaks '
            'side by side, and cheer every on-time morning.',
        actions: [
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(
              label: 'Add your first friend',
              onPressed: () => _openAddSheet(),
            ),
          ),
          GhostButton(
            label: 'Join a group',
            onPressed: () => _openAddSheet(CrewAddMode.joinGroup),
          ),
        ],
      ),
    );
  }

  // ---- Cheer them on -------------------------------------------------------

  Widget _feedSection(AsyncValue<List<FeedItem>> feed) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SectionLabel('Cheer them on'),
            const Spacer(),
            GestureDetector(
              key: const Key('crew-feed-see-all'),
              behavior: HitTestBehavior.opaque,
              onTap: () => _push(const ActivityFeedScreen()),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                child: Text('See all',
                    style: RiseText.caption.copyWith(
                        color: RiseColors.text, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        feed.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(child: RiseSpinner()),
          ),
          error: (_, __) => RiseErrorCard(
            message: "Couldn't load your crew's activity.",
            onRetry: () => ref.invalidate(crewFeedProvider),
          ),
          data: (items) => items.isEmpty
              ? _quietFeedCard()
              : Column(children: [
                  for (final item in items.take(3)) CrewFeedTile(item: item),
                ]),
        ),
      ],
    );
  }

  Widget _quietFeedCard() {
    return RiseCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(
          children: [
            Icon(Icons.wb_sunny_outlined,
                size: 20, color: RiseColors.textFaint),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                  'Quiet for now — every wake-up lands here, ready for a cheer.',
                  style: RiseText.caption),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Groups --------------------------------------------------------------

  Widget _groupsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        SectionLabel('Groups'),
        SizedBox(height: 12),
        GroupsTab(),
      ],
    );
  }
}

/// A 44px round icon action in the Crew header, with an optional count badge
/// (unread voice clips, waiting requests).
class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon({
    super.key,
    required this.icon,
    required this.badge,
    required this.onTap,
    required this.semanticLabel,
  });

  final IconData icon;
  final int badge;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: RiseColors.card,
                  shape: BoxShape.circle,
                  border: Border.all(color: RiseColors.border),
                  boxShadow: RiseShadows.card,
                ),
                child: Icon(icon, size: 20, color: RiseColors.text),
              ),
              if (badge > 0)
                Positioned(
                  top: -3,
                  right: -3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 2),
                    constraints: const BoxConstraints(minWidth: 18),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: RiseColors.primary,
                      borderRadius: BorderRadius.circular(RiseRadii.pill),
                      border: Border.all(color: RiseColors.appBg, width: 1.5),
                    ),
                    child: Text('$badge',
                        style: RiseText.mono(
                            size: 10,
                            weight: FontWeight.w600,
                            color: RiseColors.primaryText)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Signed-out (or unconfigured): a warm hero. With auth configured the primary
/// action signs in right here; unconfigured builds explain instead of showing
/// a dead control.
class _CrewSignedOut extends ConsumerStatefulWidget {
  const _CrewSignedOut({required this.configured});

  final bool configured;

  @override
  ConsumerState<_CrewSignedOut> createState() => _CrewSignedOutState();
}

class _CrewSignedOutState extends ConsumerState<_CrewSignedOut> {
  bool _busy = false;

  Future<void> _signIn() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(authServiceProvider).signInWithGoogle();
    } catch (_) {
      if (mounted) {
        RiseToast.show(context, 'Sign-in was cancelled.',
            kind: RiseToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: CrewHero(
            icon: Icons.groups_outlined,
            title: 'Wake up together',
            body: 'See your crew get up in real time, keep streaks side by '
                'side, and cheer every on-time morning.',
            actions: [
              if (widget.configured)
                SizedBox(
                  width: double.infinity,
                  child: PrimaryButton(
                    label: 'Sign in with Google',
                    icon: Icons.login,
                    onPressed: _busy ? null : _signIn,
                  ),
                )
              else
                Text('Accounts are coming soon to this build.',
                    textAlign: TextAlign.center, style: RiseText.caption),
            ],
          ),
        ),
      ),
    );
  }
}
