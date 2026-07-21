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

/// Maps the domain [CrewStatus] to its presentation. Deliberately NOT an
/// exhaustive switch: the `default` arm means a future enum value (say, an
/// `out` status) degrades to the quiet fallback instead of breaking the UI —
/// add its dedicated arm here when the domain grows.
CrewStatusStyle crewStatusStyle(CrewStatus status) {
  switch (status) {
    case CrewStatus.waking:
      return CrewStatusStyle(
        color: RiseColors.waking,
        word: 'Waking',
        line: 'Waking up now',
        rank: 0,
      );
    case CrewStatus.awake:
      return CrewStatusStyle(
        color: RiseColors.positive,
        word: 'Awake',
        line: 'Up and about',
        rank: 1,
      );
    case CrewStatus.asleep:
      return CrewStatusStyle(
        color: RiseColors.asleep,
        word: 'Asleep',
        line: 'Probably asleep',
        rank: 2,
      );
    default: // CrewStatus.unknown today; any future status lands here safely.
      return CrewStatusStyle(
        color: RiseColors.textFaint,
        word: 'Quiet',
        line: 'No status right now',
        rank: 3,
      );
  }
}
