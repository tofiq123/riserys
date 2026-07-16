import 'package:flutter/widgets.dart';

import '../../domain/alarm.dart';
import '../components/slide_to_wake.dart';
import 'hold_mission.dart';
import 'math_mission.dart';
import 'memory_mission.dart';
import 'tap_mission.dart';

/// Structurally a `MissionBuilder` (see `ring_screen.dart`): picks the mission
/// widget for [alarm.mission]. `'none'` never reaches here — RingScreen shows
/// slide-to-wake for it — so it maps to an empty box defensively.
Widget buildMission(BuildContext context, Alarm alarm, VoidCallback onSolved) {
  switch (alarm.mission) {
    case 'math':
      return MathMission(diff: alarm.missionDiff, onSolved: onSolved);
    case 'hold':
      return HoldMission(diff: alarm.missionDiff, onSolved: onSolved);
    case 'tap':
      return TapMission(diff: alarm.missionDiff, onSolved: onSolved);
    case 'memory':
      return MemoryMission(diff: alarm.missionDiff, onSolved: onSolved);
    default:
      return SlideToWake(onWake: onSolved);
  }
}
