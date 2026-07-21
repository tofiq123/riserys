import 'package:flutter/material.dart';

import '../../domain/achievements.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Fixed capture dimensions for the shareable card. The offscreen
/// RepaintBoundary and this widget agree on the same size so captures are
/// deterministic.
const double kShareCardWidth = 360;
const double kShareCardHeight = 470;

/// A polished, self-contained progress card built for sharing: streak,
/// consistency, and a badge or two, on a dark branded surface. Pure and
/// stateless — takes plain values, so it renders identically offscreen (for
/// capture) and in a widget test.
///
/// It celebrates what the user *did* — a streak, an earned badge — never a
/// label about who they are.
class ShareableStatsCard extends StatelessWidget {
  const ShareableStatsCard({
    super.key,
    required this.streakDays,
    required this.bestStreak,
    this.consistency,
    this.badges = const [],
    this.handle,
  });

  final int streakDays;
  final int bestStreak;

  /// 0–100 consistency, or null when there isn't enough data yet.
  final int? consistency;

  /// Earned badges to spotlight; the first two are shown.
  final List<Achievement> badges;

  /// The user's '@handle', or null when signed out / unclaimed.
  final String? handle;

  @override
  Widget build(BuildContext context) {
    const white70 = Color(0xB3FAFAFA);
    final spotlight = badges.take(2).toList();
    return SizedBox(
      width: kShareCardWidth,
      height: kShareCardHeight,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF18181B), Color(0xFF27272A)],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.wb_twilight,
                      color: RiseColors.waking, size: 22),
                  const SizedBox(width: 8),
                  Text('RISE',
                      style: RiseText.body.copyWith(
                          color: RiseColors.primaryText,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2)),
                  const Spacer(),
                  if (handle != null)
                    Text(handle!,
                        style:
                            RiseText.mono(size: 12.5, color: white70)),
                ],
              ),
              const Spacer(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: Icon(Icons.local_fire_department,
                        color: RiseColors.waking, size: 40),
                  ),
                  const SizedBox(width: 8),
                  Text('$streakDays',
                      style: RiseText.mono(
                          size: 96,
                          weight: FontWeight.w700,
                          color: RiseColors.primaryText)),
                ],
              ),
              Text('day streak',
                  style: RiseText.body
                      .copyWith(color: white70, fontWeight: FontWeight.w600)),
              const SizedBox(height: 22),
              Row(
                children: [
                  _stat('Best', '$bestStreak'),
                  const SizedBox(width: 14),
                  _stat('Consistency',
                      consistency != null ? '$consistency' : '—'),
                ],
              ),
              const Spacer(),
              if (spotlight.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [for (final b in spotlight) _badgePill(b)],
                )
              else
                Text('Just getting started.',
                    style: RiseText.caption.copyWith(color: white70)),
              const SizedBox(height: 18),
              Text('Waking up, 100%.',
                  style: RiseText.caption.copyWith(color: white70)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0x1AFAFAFA),
          borderRadius: BorderRadius.circular(RiseRadii.base),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: RiseText.mono(
                    size: 22,
                    weight: FontWeight.w700,
                    color: RiseColors.primaryText)),
            const SizedBox(height: 2),
            Text(label,
                style: RiseText.caption.copyWith(color: const Color(0x99FAFAFA))),
          ],
        ),
      ),
    );
  }

  Widget _badgePill(Achievement a) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0x1AFAFAFA),
        borderRadius: BorderRadius.circular(RiseRadii.pill),
        border: Border.all(color: const Color(0x33FAFAFA)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, size: 15, color: RiseColors.positive),
          const SizedBox(width: 7),
          Text(a.title,
              style: RiseText.caption.copyWith(
                  color: RiseColors.primaryText, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
