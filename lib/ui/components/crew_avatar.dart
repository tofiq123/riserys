import 'package:flutter/widgets.dart';

import '../../domain/crew_status.dart';
import '../theme/avatar_color.dart';
import '../theme/tokens.dart';
import 'crew_status_style.dart';

/// The crew identity mark: a coloured initial disc, optionally wrapped in a
/// 2px status ring (with a breathing gap) when [ring] is given. The ring
/// colour comes from [crewStatusStyle], so every surface agrees on what each
/// status looks like.
class CrewAvatar extends StatelessWidget {
  const CrewAvatar({
    super.key,
    required this.username,
    required this.colorHex,
    this.size = 40,
    this.ring,
  });

  final String username;
  final String colorHex;

  /// Diameter of the inner disc. With a [ring] the total footprint is
  /// `size + 9` (2px ring + 2.5px gap each side).
  final double size;

  /// When non-null, draws the live-status ring around the disc.
  final CrewStatus? ring;

  @override
  Widget build(BuildContext context) {
    final disc = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: avatarColorFromHex(colorHex),
        shape: BoxShape.circle,
      ),
      child: Text(
        (username.isEmpty ? '?' : username).characters.first.toUpperCase(),
        style: TextStyle(
          fontFamily: 'Geist',
          fontSize: size * 0.42,
          fontWeight: FontWeight.w700,
          color: RiseColors.primaryText,
        ),
      ),
    );
    final status = ring;
    if (status == null) return disc;
    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: crewStatusStyle(status).color, width: 2),
      ),
      child: disc,
    );
  }
}
