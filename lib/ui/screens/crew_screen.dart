import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/auth/auth_service.dart';
import '../../domain/clock_format.dart';
import '../../domain/crew_member.dart';
import '../../domain/crew_state.dart';
import '../../domain/crew_status.dart';
import '../../domain/morning_line.dart';
import '../components/crew_add_sheet.dart';
import '../components/crew_avatar.dart';
import '../components/crew_entrance.dart';
import '../components/crew_requests_sheet.dart';
import '../components/date_eyebrow.dart';
import '../components/hero_card.dart';
import '../components/morning_line_view.dart';
import '../components/rise_card.dart';
import '../components/rise_motion.dart';
import '../components/rise_skeleton.dart';
import '../components/section_label.dart';
import '../components/toast.dart';
import '../state/alarm_providers.dart';
import '../state/auth_providers.dart';
import '../state/crew_providers.dart';
import '../state/feed_providers.dart';
import '../state/group_providers.dart';
import '../state/settings_providers.dart';
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

/// The Crew tab: one morning, on a line.
///
/// A vertical time axis with a live marker at the current minute. Wake-ups land
/// above it at the minute they happened; everyone still under sits below with
/// their live status. Through the morning, people cross the line.
///
/// The screen takes three shapes, because the product is about one moment in
/// the day and pretending otherwise wasted the app's best asset: the **window**
/// (live, amber, a marker), the **wrapped** record once the mornings are done,
/// and **tonight**, where the only useful fact is your own next alarm.
///
/// Signed out (or an unconfigured backend) shows a dawn hero instead — the
/// whole app stays usable without an account.
class CrewScreen extends ConsumerStatefulWidget {
  const CrewScreen({super.key, this.clock});

  /// Test seam: fixes "now" so a phase can be asserted. Null in production,
  /// where the ticker below supplies it.
  final DateTime? clock;

  @override
  ConsumerState<CrewScreen> createState() => _CrewScreenState();
}

class _CrewScreenState extends ConsumerState<CrewScreen> {
  /// The screen's only clock. One timer, one `setState`, so the marker and the
  /// hero count stay live without anything else in the tree reading
  /// `DateTime.now()` during build.
  late DateTime _now = widget.clock ?? DateTime.now();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    if (widget.clock == null) {
      _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) setState(() => _now = DateTime.now());
      });
    }
    // Stale-while-revalidate: the session caches render instantly; a reopen
    // quietly refreshes anything already loaded (Riverpod keeps the previous
    // data during the refetch, so nothing flickers). First loads are left
    // alone — the warmup host already started them.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Signed-in only: reading these while the account is still resolving
      // would initialize them too early and double-fetch once it lands.
      if (ref.read(accountProvider).valueOrNull == null) return;
      if (ref.read(crewFeedProvider).hasValue) {
        ref.invalidate(crewFeedProvider);
      }
      if (ref.read(myGroupsProvider).hasValue) {
        ref.invalidate(myGroupsProvider);
      }
      if (ref.read(voiceInboxProvider).hasValue) {
        ref.invalidate(voiceInboxProvider);
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _push(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  Future<void> _refresh() async {
    ref.invalidate(crewFeedProvider);
    ref.invalidate(myGroupsProvider);
    ref.invalidate(voiceInboxProvider);
    // Settle before the indicator retracts; a failed fetch just keeps the
    // section's own error card — never breaks the gesture. The crew itself
    // reloads through its service: friendships have no Realtime, so this is
    // the only way a peer's new request/accept becomes visible on demand.
    await Future.wait<Object?>([
      ref.read(crewServiceProvider).reload(),
      ref.read(crewFeedProvider.future),
      ref.read(myGroupsProvider.future),
      ref.read(voiceInboxProvider.future),
    ]).catchError((_) => const <Object?>[]);
  }

  Future<void> _openAddSheet([CrewAddMode mode = CrewAddMode.friend]) async {
    final group = await showCrewAddSheet(
      context,
      initial: mode,
      onCrewLimit: () => openPaywall(context),
    );
    if (group != null && mounted) _push(GroupDetailScreen(group: group));
  }

  void _openEntry(MorningEntry e) =>
      _push(FriendDetailScreen(member: e.toMember()));

  /// Leaving a cheer. Optimistic by design: the tally is a nicety, so a failure
  /// only ever refreshes the feed back to the truth.
  Future<void> _cheer(MorningEntry entry, String emoji) async {
    final feedId = entry.feedId;
    if (feedId == null) return;
    final already =
        entry.reactions.any((r) => r.emoji == emoji && r.reactedByMe);
    try {
      final service = ref.read(feedServiceProvider);
      if (already) {
        await service.unreact(feedId, emoji);
      } else {
        await service.react(feedId, emoji);
        if (mounted) RiseToast.show(context, 'Cheered $emoji');
      }
    } catch (_) {
      // Best-effort — the invalidate below restores the true tally.
    }
    ref.invalidate(crewFeedProvider);
  }

  @override
  Widget build(BuildContext context) {
    final accountAsync = ref.watch(accountProvider);
    final account = accountAsync.valueOrNull;
    if (account == null) {
      // Loading with nothing known yet is NOT signed out: render a quiet
      // skeleton until the truth arrives, so sign-in can never flash.
      if (accountAsync.isLoading) return const _CrewRestoringSkeleton();
      final configured = ref.watch(authServiceProvider) is! DisabledAuthService;
      return _CrewSignedOut(configured: configured);
    }

    final crewAsync = ref.watch(crewProvider);
    final crewLoading = crewAsync.isLoading && !crewAsync.hasValue;
    final crew = crewAsync.valueOrNull ?? CrewState.empty;
    final statuses =
        ref.watch(crewStatusesProvider).valueOrNull ?? const <String, CrewStatus>{};
    final feedAsync = ref.watch(crewFeedProvider);
    final use24h =
        ref.watch(currentSettingsProvider.select((s) => s.use24HourTime));

    final line = buildMorningLine(
      now: _now,
      friends: crew.friends,
      statuses: statuses,
      feed: feedAsync.valueOrNull ?? const [],
      myId: account.id,
      myUsername: account.username ?? '',
      myDisplayName: account.displayName,
      myAvatarColor: account.avatarColor,
      myStatus: statuses[account.id] ?? CrewStatus.unknown,
    );
    final alone = crew.friends.isEmpty;

    return SafeArea(
      child: RefreshIndicator(
        color: RiseColors.primary,
        backgroundColor: RiseColors.card,
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
              RiseSpacing.screen, 8, RiseSpacing.screen, 40),
          children: [
            CrewEntrance(index: 0, child: _header(crew, line.phase)),
            const SizedBox(height: 18),
            if (crew.incoming.isNotEmpty) ...[
              CrewEntrance(index: 1, child: _requestsPill(crew.incoming)),
              const SizedBox(height: 16),
            ],
            CrewEntrance(
              index: 2,
              child: RiseFade(
                child: crewLoading
                    ? RiseFade.keyed('loading', const _HeroSkeleton())
                    : RiseFade.keyed('hero', _hero(line, alone, use24h)),
              ),
            ),
            const SizedBox(height: 24),
            // A failed feed must never look like "nothing happened this
            // morning". The line still renders from live status; this says
            // what is missing and offers the retry.
            if (feedAsync.hasError && !feedAsync.hasValue) ...[
              _FeedErrorNotice(
                  onRetry: () => ref.invalidate(crewFeedProvider)),
              const SizedBox(height: 16),
            ],
            CrewEntrance(
              index: 3,
              child: RiseFade(
                child: crewLoading
                    ? RiseFade.keyed('loading', const _LineSkeleton())
                    : RiseFade.keyed(
                        'line',
                        MorningLineView(
                          line: line,
                          now: _now,
                          use24h: use24h,
                          onOpen: _openEntry,
                          onCheer: _cheer,
                          onSeeAll: () => _push(const ActivityFeedScreen()),
                          footer: alone ? _inviteOnTheLine() : null,
                        )),
              ),
            ),
            const SizedBox(height: 26),
            CrewEntrance(index: 4, child: _groupsSection()),
          ],
        ),
      ),
    );
  }

  // ---- Header --------------------------------------------------------------

  /// The title says what is happening, not what the tab is called — the tab bar
  /// already says "Crew".
  static String phaseTitle(MorningPhase phase) => switch (phase) {
        MorningPhase.window => 'Wake window',
        MorningPhase.wrapped => "Today's mornings",
        MorningPhase.tonight => 'Tonight',
      };

  Widget _header(CrewState crew, MorningPhase phase) {
    final clips = ref.watch(voiceInboxProvider).valueOrNull ?? const [];
    final unread = clips.where((c) => !c.isPlayed).length;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const DateEyebrow(),
              const SizedBox(height: 3),
              Text(phaseTitle(phase),
                  style: RiseText.display,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        const SizedBox(width: 8),
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

  // ---- Requests ------------------------------------------------------------

  /// Slimmer than the old banner: a request is a nudge, not a headline.
  Widget _requestsPill(List<CrewMember> incoming) {
    final first = incoming.first;
    final name =
        first.displayName.isNotEmpty ? first.displayName : '@${first.username}';
    final title = incoming.length == 1
        ? '$name wants to join your crew'
        : '${incoming.length} people want to join your crew';
    return RisePressable(
      key: const Key('crew-requests-banner'),
      onTap: () => showCrewRequestsSheet(context),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
        decoration: BoxDecoration(
          color: RiseColors.card,
          borderRadius: BorderRadius.circular(RiseRadii.pill),
          border: Border.all(color: RiseColors.border),
          boxShadow: RiseShadows.card,
        ),
        child: Row(
          children: [
            SizedBox(
              width: incoming.length > 1 ? 44 : 30,
              height: 30,
              child: Stack(
                children: [
                  for (var i = 0; i < (incoming.length > 1 ? 2 : 1); i++)
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
                          size: 26,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title,
                  style: RiseText.body
                      .copyWith(fontSize: 13.5, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 6),
            Text('Review',
                style: RiseText.caption.copyWith(
                    color: RiseColors.text, fontWeight: FontWeight.w600)),
            Icon(Icons.chevron_right, size: 16, color: RiseColors.textFaint),
          ],
        ),
      ),
    );
  }

  // ---- The three heroes ----------------------------------------------------

  Widget _hero(MorningLine line, bool alone, bool use24h) => switch (line.phase) {
        MorningPhase.window => _windowHero(line, alone),
        MorningPhase.wrapped => _wrappedHero(line),
        MorningPhase.tonight => _tonightHero(line, use24h),
      };

  Widget _windowHero(MorningLine line, bool alone) {
    final up = line.up.length;
    final first = line.first;
    return HeroCard(
      key: const Key('crew-hero-window'),
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
              Text('LIVE',
                  style: RiseText.sectionLabel
                      .copyWith(color: RiseColors.primaryText)),
            ],
          ),
          const SizedBox(height: 12),
          _CountLine(up: up, total: line.total),
          const SizedBox(height: 5),
          Opacity(
            opacity: 0.72,
            child: Text(
              first == null
                  ? (alone
                      ? "Your morning starts the line."
                      : 'All quiet — be the first up.')
                  : '${first.shortName} ${first.isMe ? "were" : "was"} first, '
                      '${_hhmm(first.wokeAt!)}.',
              style:
                  RiseText.caption.copyWith(color: RiseColors.primaryText),
            ),
          ),
          if (line.total > 0) ...[
            const SizedBox(height: 16),
            _Pips(filled: up, total: line.total),
          ],
        ],
      ),
    );
  }

  Widget _wrappedHero(MorningLine line) {
    final missed = line.missed;
    final first = line.first;
    return HeroCard(
      key: const Key('crew-hero-wrapped'),
      eyebrow: 'WRAPPED',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CountLine(up: line.up.length, total: line.total),
          const SizedBox(height: 5),
          Opacity(
            opacity: 0.72,
            child: Text(
              [
                if (missed.isNotEmpty && missed.length <= 2)
                  'Everyone but ${missed.map((e) => e.shortName).join(" and ")}.',
                if (first != null)
                  '${first.shortName} ${first.isMe ? "were" : "was"} first at '
                      '${_hhmm(first.wokeAt!)}.',
              ].join(' '),
              style:
                  RiseText.caption.copyWith(color: RiseColors.primaryText),
            ),
          ),
          if (line.total > 0) ...[
            const SizedBox(height: 16),
            _Pips(filled: line.up.length, total: line.total),
          ],
        ],
      ),
    );
  }

  /// At bedtime the crew's morning is over; the one fact worth a headline is
  /// your own next alarm.
  Widget _tonightHero(MorningLine line, bool use24h) {
    final next = ref.watch(nextOccurrenceProvider).valueOrNull;
    final down = line.pending.where((e) => !e.isMe).length;
    final woke = line.up.length;

    if (next == null) {
      return HeroCard(
        key: const Key('crew-hero-tonight'),
        eyebrow: 'TONIGHT',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('No alarm set for the morning.',
                style: RiseText.title.copyWith(
                    fontSize: 19, color: RiseColors.primaryText)),
            const SizedBox(height: 6),
            Opacity(
              opacity: 0.72,
              child: Text(
                  'Set one and you\'ll be on the line with your crew.',
                  style: RiseText.caption
                      .copyWith(color: RiseColors.primaryText)),
            ),
          ],
        ),
      );
    }

    final fireAt = next.fireAt.toLocal();
    final until = fireAt.difference(_now);
    return HeroCard(
      key: const Key('crew-hero-tonight'),
      eyebrow: 'YOUR ALARM',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                    formatClock(fireAt.hour, fireAt.minute, use24h: use24h),
                    style: RiseText.mono(
                        size: 40,
                        weight: FontWeight.w600,
                        color: RiseColors.primaryText,
                        letterSpacing: -1.4),
                    maxLines: 1),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Opacity(
                  opacity: 0.75,
                  child: Text('in ${_countdown(until)}',
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
            opacity: 0.72,
            child: Text(next.label,
                style:
                    RiseText.caption.copyWith(color: RiseColors.primaryText),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          if (line.total > 1) ...[
            const SizedBox(height: 16),
            Container(
                height: 1,
                color: RiseColors.primaryText.withValues(alpha: 0.18)),
            const SizedBox(height: 14),
            Opacity(
              opacity: 0.72,
              child: Text(
                  '$down of ${line.total - 1} in your crew already down · '
                  '$woke made it this morning',
                  style: RiseText.caption
                      .copyWith(color: RiseColors.primaryText),
                  maxLines: 2),
            ),
          ],
        ],
      ),
    );
  }

  String _hhmm(DateTime t) {
    final use24h =
        ref.read(currentSettingsProvider.select((s) => s.use24HourTime));
    final l = t.toLocal();
    return formatClock(l.hour, l.minute, use24h: use24h);
  }

  static String _countdown(Duration d) {
    if (d.isNegative) return 'moments';
    final h = d.inHours, m = d.inMinutes % 60;
    if (h == 0) return '${m}m';
    return '${h}h ${m}m';
  }

  // ---- Empty state ---------------------------------------------------------

  /// The invitation sits ON the line, where the other people would be — so the
  /// empty state teaches the component instead of describing it.
  Widget _inviteOnTheLine() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: RiseColors.surface2,
        borderRadius: BorderRadius.circular(RiseRadii.base),
        border: Border.all(color: RiseColors.border, style: BorderStyle.solid),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: EdgeInsets.only(left: i == 0 ? 0 : 8),
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: RiseColors.border, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text('This is where your crew shows up.',
              style: RiseText.body.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
              "Add someone and you'll see the minute they wake — and they'll "
              'see you.',
              style: RiseText.caption),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: _WideButton(
              key: const Key('crew-add-first-friend'),
              label: 'Add a friend',
              filled: true,
              onTap: () => _openAddSheet(),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: _WideButton(
              key: const Key('crew-join-group'),
              label: 'Join a group with a code',
              onTap: () => _openAddSheet(CrewAddMode.joinGroup),
            ),
          ),
        ],
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

/// The wakes could not be fetched. Says exactly what is missing — the rest of
/// the line still works from live status — and offers the retry.
class _FeedErrorNotice extends StatelessWidget {
  const _FeedErrorNotice({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return RiseCard(
      radius: RiseRadii.base,
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, size: 18, color: RiseColors.textDim),
          const SizedBox(width: 11),
          Expanded(
            child: Text("Couldn't load this morning's wake-ups.",
                style: RiseText.caption),
          ),
          const SizedBox(width: 8),
          Semantics(
            button: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onRetry,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                child: Text('Retry',
                    style: RiseText.caption.copyWith(
                        color: RiseColors.accent,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "3 of 6 up" — the count is the headline because it is the answer.
class _CountLine extends StatelessWidget {
  const _CountLine({required this.up, required this.total});

  final int up, total;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(
          child: RiseCountUp(
            value: up,
            style: RiseText.mono(
                size: 40,
                weight: FontWeight.w600,
                color: RiseColors.primaryText,
                letterSpacing: -1.4),
          ),
        ),
        const SizedBox(width: 9),
        Flexible(
          child: Opacity(
            opacity: 0.8,
            child: Text('of $total up',
                style: RiseText.body
                    .copyWith(color: RiseColors.primaryText, fontSize: 15),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.fade),
          ),
        ),
      ],
    );
  }
}

/// One pip per person — the morning's progress bar.
class _Pips extends StatelessWidget {
  const _Pips({required this.filled, required this.total});

  final int filled, total;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final count = total.clamp(1, 12);
        const gap = 5.0;
        final w = ((c.maxWidth - gap * (count - 1)) / count).clamp(6.0, 30.0);
        return Row(
          children: [
            for (var i = 0; i < count; i++)
              Padding(
                padding: EdgeInsets.only(left: i == 0 ? 0 : gap),
                child: Container(
                  width: w,
                  height: 4,
                  decoration: BoxDecoration(
                    color: RiseColors.primaryText
                        .withValues(alpha: i < filled ? 1 : 0.22),
                    borderRadius: BorderRadius.circular(RiseRadii.pill),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _WideButton extends StatelessWidget {
  const _WideButton({
    super.key,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return RisePressable(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        constraints: const BoxConstraints(minHeight: 44),
        decoration: BoxDecoration(
          color: filled ? RiseColors.primary : RiseColors.card,
          borderRadius: BorderRadius.circular(RiseRadii.sm),
          border: filled ? null : Border.all(color: RiseColors.border),
        ),
        child: Text(label,
            style: RiseText.body.copyWith(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: filled ? RiseColors.primaryText : RiseColors.text)),
      ),
    );
  }
}

/// Skeleton for the whole page while the account itself is restoring. Mirrors
/// the loaded geometry so the real content lands without a jump.
class _CrewRestoringSkeleton extends StatelessWidget {
  const _CrewRestoringSkeleton();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
            RiseSpacing.screen, 8, RiseSpacing.screen, 40),
        children: [
          Row(
            children: [
              const Expanded(child: RiseSkeleton(height: 30)),
              const SizedBox(width: 10),
              const RiseSkeletonCircle(size: 44),
              const SizedBox(width: 10),
              const RiseSkeletonCircle(size: 44),
            ],
          ),
          const SizedBox(height: 26),
          const _HeroSkeleton(),
          const SizedBox(height: 24),
          const _LineSkeleton(),
        ],
      ),
    );
  }
}

class _HeroSkeleton extends StatelessWidget {
  const _HeroSkeleton();

  @override
  Widget build(BuildContext context) =>
      const RiseSkeleton(height: 148, radius: RiseRadii.lg);
}

/// The line's loading shape: the same gutter, the same row rhythm, so nothing
/// moves when the real rows land.
class _LineSkeleton extends StatelessWidget {
  const _LineSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget row(double name) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            children: [
              const SizedBox(
                  width: MorningLineView.timeWidth,
                  child: Align(
                      alignment: Alignment.centerRight,
                      child: RiseSkeleton(width: 32, height: 11))),
              const SizedBox(
                  width: MorningLineView.railWidth,
                  child: Center(child: RiseSkeletonCircle(size: 11))),
              const RiseSkeletonCircle(size: 26),
              const SizedBox(width: 9),
              RiseSkeleton(width: name, height: 12),
            ],
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const RiseSkeleton(width: 26, height: 11),
        const SizedBox(height: 8),
        row(104),
        row(86),
        row(120),
        row(78),
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
      child: RisePressable(
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
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

/// Signed out (or unconfigured): the dawn hero. With auth configured the
/// primary action signs in right here; unconfigured builds explain instead of
/// showing a dead control. The example strip below shows the shape of the thing
/// on offer without inventing friends.
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
          padding: const EdgeInsets.all(RiseSpacing.screen),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              HeroCard(
                padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.wb_twilight, size: 30, color: RiseColors.waking),
                    const SizedBox(height: 14),
                    Text('Nobody wakes\nup alone.',
                        style: RiseText.display.copyWith(
                            fontSize: 28,
                            height: 1.08,
                            color: RiseColors.primaryText)),
                    const SizedBox(height: 10),
                    Opacity(
                      opacity: 0.75,
                      child: Text(
                          "See your crew's morning as it happens — who's up, "
                          "who's still under, and who could use a cheer.",
                          style: RiseText.body.copyWith(
                              color: RiseColors.primaryText, height: 1.45)),
                    ),
                    const SizedBox(height: 22),
                    if (widget.configured) ...[
                      SizedBox(
                        width: double.infinity,
                        child: HeroButton(
                          label: 'Continue with Google',
                          icon: Icons.login,
                          onPressed: _busy ? null : _signIn,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: Opacity(
                          opacity: 0.6,
                          child: Text('Your alarms work without an account.',
                              style: RiseText.caption.copyWith(
                                  color: RiseColors.primaryText,
                                  fontSize: 11.5)),
                        ),
                      ),
                    ] else
                      Opacity(
                        opacity: 0.7,
                        child: Text('Accounts are coming soon to this build.',
                            style: RiseText.caption
                                .copyWith(color: RiseColors.primaryText)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const _ExampleStrip(),
            ],
          ),
        ),
      ),
    );
  }
}

/// A miniature of the line, labelled as an example. Shows what the tab does
/// without fabricating people.
class _ExampleStrip extends StatelessWidget {
  const _ExampleStrip();

  @override
  Widget build(BuildContext context) {
    Widget dot(Color color, {bool hollow = false}) => Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: hollow ? RiseColors.card : color,
            border: hollow ? Border.all(color: color, width: 2) : null,
          ),
        );
    return RiseCard(
      radius: RiseRadii.base,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('EXAMPLE', style: RiseText.sectionLabel.copyWith(fontSize: 9.5)),
          const SizedBox(height: 12),
          Row(
            children: [
              dot(RiseColors.positive),
              const SizedBox(width: 6),
              Text('05:42', style: RiseText.mono(size: 11, color: RiseColors.textDim)),
              const SizedBox(width: 10),
              dot(RiseColors.positive),
              const SizedBox(width: 6),
              Text('05:58', style: RiseText.mono(size: 11, color: RiseColors.textDim)),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                    height: 1.5,
                    color: RiseColors.waking.withValues(alpha: 0.5)),
              ),
              const SizedBox(width: 7),
              Text('NOW',
                  style: RiseText.mono(
                      size: 9.5,
                      weight: FontWeight.w600,
                      color: RiseColors.waking,
                      letterSpacing: 1.2)),
              const SizedBox(width: 8),
              dot(RiseColors.waking, hollow: true),
              const SizedBox(width: 6),
              dot(RiseColors.border, hollow: true),
            ],
          ),
          const SizedBox(height: 10),
          Text('Two up, one waking, one still under.',
              style: RiseText.caption.copyWith(fontSize: 11.5)),
        ],
      ),
    );
  }
}
