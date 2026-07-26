import 'package:flutter/material.dart';

import '../../domain/clock_format.dart';
import '../../domain/crew_status.dart';
import '../../domain/feed_item.dart';
import '../../domain/morning_line.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'crew_avatar.dart';
import 'crew_status_style.dart';
import 'rise_motion.dart';

/// The Crew tab's spine: one vertical time axis with a live marker on it.
///
/// Everything above the marker already happened, at the minute it happened;
/// everything below hasn't yet. Through the morning people cross the line. This
/// replaces the old status chip strip AND the separate "Cheer them on" feed —
/// they were the same six people listed twice, and reconciling them was work the
/// user should never have had to do.
///
/// Identity is never left to colour: every row states its own verdict in words
/// ("on time", "waking now", "no wake logged"), so the rail dots are
/// reinforcement rather than the only signal.
class MorningLineView extends StatelessWidget {
  const MorningLineView({
    super.key,
    required this.line,
    required this.now,
    required this.onOpen,
    this.onCheer,
    this.use24h = true,
    this.footer,
    this.maxUp = 8,
    this.onSeeAll,
  });

  final MorningLine line;
  final DateTime now;

  /// Opening a person's page. Your own row is not a friend to inspect, so it is
  /// never wired to this.
  final void Function(MorningEntry) onOpen;

  /// Leaving an emoji on a wake. Null hides every cheer affordance (a signed-out
  /// or preview rendering).
  final void Function(MorningEntry entry, String emoji)? onCheer;

  final bool use24h;

  /// Rendered on the line below the last row — the empty state's invitation.
  final Widget? footer;

  /// A long crew is truncated rather than scrolled forever; the rest is one tap
  /// away.
  final int maxUp;
  final VoidCallback? onSeeAll;

  static const double timeWidth = 46;
  static const double railWidth = 24;
  static const double _railCentre = timeWidth + railWidth / 2;

  @override
  Widget build(BuildContext context) {
    final shownUp =
        line.up.length > maxUp ? line.up.sublist(line.up.length - maxUp) : line.up;
    final hidden = line.up.length - shownUp.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            line.phase == MorningPhase.window ? 'UP' : 'THE MORNING',
            style: RiseText.sectionLabel,
          ),
        ),
        Stack(
          children: [
            // The axis itself. Behind the rows so the dots sit on it.
            Positioned(
              left: _railCentre - 0.5,
              top: 6,
              bottom: 10,
              width: 1,
              child: ColoredBox(color: RiseColors.border),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hidden > 0)
                  _MoreRow(count: hidden, onTap: onSeeAll),
                if (shownUp.isEmpty && line.phase == MorningPhase.window)
                  const _NobodyYetRow(),
                for (final e in shownUp)
                  _UpRow(
                    entry: e,
                    use24h: use24h,
                    onOpen: e.isMe ? null : () => onOpen(e),
                    onCheer: onCheer == null || e.feedId == null
                        ? null
                        : (emoji) => onCheer!(e, emoji),
                  ),
                if (line.phase == MorningPhase.window)
                  NowMarker(now: now, use24h: use24h),
                for (final e in line.pending)
                  _PendingRow(
                    entry: e,
                    wrapped: line.phase == MorningPhase.wrapped,
                    onOpen: e.isMe ? null : () => onOpen(e),
                    onCheer: onCheer == null
                        ? null
                        : () => onOpen(e), // cheering a waking friend opens them
                  ),
                if (footer != null)
                  Padding(
                    padding: const EdgeInsets.only(
                        left: timeWidth + railWidth, top: 10),
                    child: footer,
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

/// The live marker. Amber, labelled, and the one thing on the screen that
/// breathes — scoped to its own `RepaintBoundary` so nothing else repaints with
/// it, and static under reduced motion.
class NowMarker extends StatefulWidget {
  const NowMarker({super.key, required this.now, this.use24h = true});

  final DateTime now;
  final bool use24h;

  @override
  State<NowMarker> createState() => _NowMarkerState();
}

class _NowMarkerState extends State<NowMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) {
      if (_c.isAnimating) _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final local = widget.now.toLocal();
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return SizedBox(
      height: 26,
      child: Row(
        children: [
          SizedBox(
            width: MorningLineView.timeWidth,
            child: Text(
              formatClock(local.hour, local.minute, use24h: widget.use24h),
              textAlign: TextAlign.right,
              style: RiseText.mono(
                  size: 11.5,
                  weight: FontWeight.w600,
                  color: RiseColors.waking),
            ),
          ),
          SizedBox(
            width: MorningLineView.railWidth,
            child: Center(
              child: RepaintBoundary(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: reduce
                      ? const _NowDot(scale: 1.3, opacity: 0.4)
                      : AnimatedBuilder(
                          animation: _c,
                          builder: (_, __) {
                            final t = Curves.easeOut.transform(_c.value);
                            return _NowDot(
                                scale: 0.7 + t * 0.9,
                                opacity: (1 - t).clamp(0.0, 1.0) * 0.9);
                          },
                        ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Container(
                    width: 14,
                    height: 1.5,
                    color: RiseColors.waking.withValues(alpha: 0.55)),
                const SizedBox(width: 7),
                Text('NOW',
                    style: RiseText.mono(
                        size: 10,
                        weight: FontWeight.w600,
                        color: RiseColors.waking,
                        letterSpacing: 1.4)),
                const SizedBox(width: 7),
                Expanded(
                  child: Container(
                      height: 1.5,
                      color: RiseColors.waking.withValues(alpha: 0.35)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NowDot extends StatelessWidget {
  const _NowDot({required this.scale, required this.opacity});

  final double scale, opacity;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Transform.scale(
          scale: scale,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                  color: RiseColors.waking.withValues(alpha: opacity),
                  width: 1.5),
            ),
          ),
        ),
        Container(
          width: 9,
          height: 9,
          decoration:
              BoxDecoration(shape: BoxShape.circle, color: RiseColors.waking),
        ),
      ],
    );
  }
}

/// The rail's dot for one person. Four silhouettes, each also stated in words
/// on the row beside it: filled (up, on time), ring (up), pulsing amber ring
/// (mid-wake), faint hollow (still under), dash (no wake at all).
enum _Dot { filled, ring, waking, quiet, none }

class _RailDot extends StatelessWidget {
  const _RailDot(this.kind);

  final _Dot kind;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: MorningLineView.railWidth,
      child: Center(
        child: switch (kind) {
          _Dot.filled => Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: RiseColors.positive)),
          _Dot.ring => Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: RiseColors.card,
                border: Border.all(color: RiseColors.text, width: 2.2),
              )),
          _Dot.waking => Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: RiseColors.card,
                border: Border.all(color: RiseColors.waking, width: 2.2),
              )),
          _Dot.quiet => Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: RiseColors.card,
                border: Border.all(color: RiseColors.border, width: 1.6),
              )),
          _Dot.none => Container(
              width: 11,
              height: 2,
              decoration: BoxDecoration(
                color: RiseColors.textFaint,
                borderRadius: BorderRadius.circular(2),
              )),
        },
      ),
    );
  }
}

/// A morning that already happened.
class _UpRow extends StatelessWidget {
  const _UpRow({
    required this.entry,
    required this.use24h,
    this.onOpen,
    this.onCheer,
  });

  final MorningEntry entry;
  final bool use24h;
  final VoidCallback? onOpen;
  final void Function(String emoji)? onCheer;

  @override
  Widget build(BuildContext context) {
    final woke = entry.wokeAt!.toLocal();
    return RisePressable(
      key: Key('line-row-${entry.id}'),
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: MorningLineView.timeWidth,
                  child: Text(
                    formatClock(woke.hour, woke.minute, use24h: use24h),
                    textAlign: TextAlign.right,
                    style: RiseText.mono(
                        size: 12, weight: FontWeight.w500,
                        color: RiseColors.textDim),
                  ),
                ),
                _RailDot(entry.onTime ? _Dot.filled : _Dot.ring),
                CrewAvatar(
                    username: entry.username,
                    colorHex: entry.avatarColor,
                    size: 26),
                const SizedBox(width: 9),
                Flexible(
                  child: Text(entry.fullName,
                      style: RiseText.body.copyWith(
                          fontSize: 14.5, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                Text(entry.verdict,
                    style: RiseText.caption.copyWith(
                      color: entry.onTime
                          ? RiseColors.positive
                          : RiseColors.textDim,
                      fontWeight:
                          entry.onTime ? FontWeight.w600 : FontWeight.w400,
                    )),
                if (entry.streak > 0) ...[
                  const Spacer(),
                  Text('🔥${entry.streak}',
                      style: RiseText.mono(
                          size: 12.5,
                          weight: FontWeight.w600,
                          color: RiseColors.textDim)),
                ],
              ],
            ),
            if (onCheer != null || entry.reactions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(
                    left: MorningLineView.timeWidth + MorningLineView.railWidth,
                    top: 7),
                child: _Reactions(entry: entry, onCheer: onCheer),
              ),
          ],
        ),
      ),
    );
  }
}

/// The tally of what the crew already left, plus one Cheer affordance that
/// opens the palette. The old design put four emoji targets on every tile —
/// twenty-four on a six-person feed.
class _Reactions extends StatefulWidget {
  const _Reactions({required this.entry, this.onCheer});

  final MorningEntry entry;
  final void Function(String emoji)? onCheer;

  @override
  State<_Reactions> createState() => _ReactionsState();
}

class _ReactionsState extends State<_Reactions> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final tallies = [
      for (final r in widget.entry.reactions)
        if (r.count > 0) r
    ];
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final r in tallies)
          _Chip(
            key: Key('line-tally-${widget.entry.id}-${r.emoji}'),
            label: '${r.emoji} ${r.count}',
            mine: r.reactedByMe,
            onTap: widget.onCheer == null
                ? null
                : () => widget.onCheer!(r.emoji),
          ),
        if (widget.onCheer != null && !_open)
          _Chip(
            key: Key('line-cheer-${widget.entry.id}'),
            label: '+ Cheer',
            dashed: true,
            onTap: () => setState(() => _open = true),
          ),
        if (widget.onCheer != null && _open)
          for (final emoji in kFeedReactionEmojis)
            _Chip(
              key: Key('line-cheer-${widget.entry.id}-$emoji'),
              label: emoji,
              onTap: () {
                widget.onCheer!(emoji);
                setState(() => _open = false);
              },
            ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    super.key,
    required this.label,
    this.mine = false,
    this.dashed = false,
    this.onTap,
  });

  final String label;
  final bool mine, dashed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return RisePressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        constraints: const BoxConstraints(minHeight: 30),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: mine ? RiseColors.accentSoft : RiseColors.surface2,
          borderRadius: BorderRadius.circular(RiseRadii.pill),
          border: Border.all(
              color: mine ? RiseColors.primary : RiseColors.border,
              width: mine ? 1.2 : 1),
        ),
        child: Text(label,
            style: RiseText.body.copyWith(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: dashed ? RiseColors.textDim : RiseColors.text)),
      ),
    );
  }
}

/// Someone still below the marker, or — once the window has closed — someone
/// whose morning never landed. Never coloured as a failure.
class _PendingRow extends StatelessWidget {
  const _PendingRow({
    required this.entry,
    required this.wrapped,
    this.onOpen,
    this.onCheer,
  });

  final MorningEntry entry;
  final bool wrapped;
  final VoidCallback? onOpen;
  final VoidCallback? onCheer;

  @override
  Widget build(BuildContext context) {
    final waking = entry.status == CrewStatus.waking;
    final style = crewStatusStyle(entry.status);
    final label = wrapped ? 'no wake logged' : style.word.toLowerCase();

    return RisePressable(
      key: Key('line-row-${entry.id}'),
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            SizedBox(
              width: MorningLineView.timeWidth,
              child: Text('—',
                  textAlign: TextAlign.right,
                  style: RiseText.mono(
                      size: 12, color: RiseColors.textFaint)),
            ),
            _RailDot(wrapped
                ? _Dot.none
                : waking
                    ? _Dot.waking
                    : _Dot.quiet),
            CrewAvatar(
                username: entry.username,
                colorHex: entry.avatarColor,
                size: 26,
                ring: waking ? CrewStatus.waking : null),
            const SizedBox(width: 9),
            Flexible(
              child: Text(entry.fullName,
                  style: RiseText.body.copyWith(
                    fontSize: 14.5,
                    fontWeight: waking ? FontWeight.w600 : FontWeight.w400,
                    color: waking ? RiseColors.text : RiseColors.textDim,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 8),
            Text(label,
                style: RiseText.caption.copyWith(
                  color: waking ? RiseColors.waking : RiseColors.textDim,
                  fontWeight: waking ? FontWeight.w600 : FontWeight.w400,
                )),
            if (waking && !entry.isMe && onCheer != null) ...[
              const Spacer(),
              _Chip(
                key: Key('line-wake-cheer-${entry.id}'),
                label: 'Cheer',
                onTap: onCheer,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The window is open but nothing has landed. Says so, rather than showing an
/// empty rail.
class _NobodyYetRow extends StatelessWidget {
  const _NobodyYetRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const SizedBox(width: MorningLineView.timeWidth),
          const _RailDot(_Dot.quiet),
          Expanded(
            child: Text('Nobody yet — the window just opened.',
                style: RiseText.caption),
          ),
        ],
      ),
    );
  }
}

/// Older wakes are truncated rather than scrolled forever.
class _MoreRow extends StatelessWidget {
  const _MoreRow({required this.count, this.onTap});

  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return RisePressable(
      key: const Key('line-see-earlier'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            const SizedBox(width: MorningLineView.timeWidth),
            const _RailDot(_Dot.quiet),
            Text('$count earlier ${count == 1 ? 'morning' : 'mornings'}',
                style: RiseText.caption
                    .copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, size: 16, color: RiseColors.textFaint),
          ],
        ),
      ),
    );
  }
}
