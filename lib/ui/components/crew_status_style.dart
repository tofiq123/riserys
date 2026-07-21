import 'dart:ui';

import '../../domain/crew_status.dart';
import '../theme/tokens.dart';

/// The ONE place a [CrewStatus] becomes presentation: the accent colour, the
/// tiny word under a member chip, the fuller line on the friend page, and the
/// sort rank for the This-morning strip.
///
/// Colours read the live [RiseColors] palette (light/dark), so never resolve
/// this inside a `const` constructor — call [crewStatusStyle] from `build`.
class CrewStatusStyle {
  const CrewStatusStyle({
    required this.color,
    required this.word,
    required this.line,
    required this.rank,
  });

  /// Ring / dot / label accent for this status.
  final Color color;

  /// The tiny word under a member chip ('Waking', 'Awake', …).
  final String word;

  /// The fuller status line on the friend detail page.
  final String line;

  /// Sort order for the This-morning strip: waking first (they need the cheer
  /// right now), then awake, asleep, and no-signal last.
  final int rank;
}

/// Maps the domain [CrewStatus] to its presentation. Every known status has a
/// dedicated arm; the `default` arm is a safety net so any future enum value
/// degrades to the quiet fallback instead of breaking the UI.
CrewStatusStyle crewStatusStyle(CrewStatus status) {
  switch (status) {
    case CrewStatus.waking:
      return CrewStatusStyle(
        color: RiseColors.waking,
        word: 'Waking',
        line: 'Waking up now',
        rank: 0,
      );
    case CrewStatus.out:
      // Awake AND left home — the strongest "up" signal. Ranks just below
      // waking so a friend who's already out shows near the top of the strip,
      // and reads celebratory (positive accent) rather than neutral.
      return CrewStatusStyle(
        color: RiseColors.positive,
        word: 'Up & out',
        line: 'Up and out the door',
        rank: 1,
      );
    case CrewStatus.awake:
      return CrewStatusStyle(
        color: RiseColors.positive,
        word: 'Awake',
        line: 'Up and about',
        rank: 2,
      );
    case CrewStatus.asleep:
      return CrewStatusStyle(
        color: RiseColors.asleep,
        word: 'Asleep',
        line: 'Probably asleep',
        rank: 3,
      );
    default: // CrewStatus.unknown today; any future status lands here safely.
      return CrewStatusStyle(
        color: RiseColors.textFaint,
        word: 'Quiet',
        line: 'No status right now',
        rank: 4,
      );
  }
}
