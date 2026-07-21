import 'package:flutter/widgets.dart';

import '../../domain/alarm.dart';
import '../components/slide_to_wake.dart';
import 'eyes_mission.dart';
import 'hold_mission.dart';
import 'math_mission.dart';
import 'memory_mission.dart';
import 'photo_mission.dart';
import 'pvt_mission.dart';
import 'qr_mission.dart';
import 'shake_mission.dart';
import 'steps_mission.dart';
import 'tap_mission.dart';
import 'typing_mission.dart';

/// Structurally a `MissionBuilder` (see `ring_screen.dart`): picks the mission
/// widget for [alarm.mission]. `'none'` never reaches here — RingScreen shows
/// slide-to-wake for it — so it maps to an empty box defensively.
///
/// [onAlertness] is forwarded only by the `'pvt'` mission (which measures a
/// 0–100 alertness score); every other mission ignores it, so their behavior
/// is unchanged.
Widget buildMission(BuildContext context, Alarm alarm, VoidCallback onSolved,
    [void Function(int alertnessScore)? onAlertness]) {
  switch (alarm.mission) {
    case 'math':
      return MathMission(diff: alarm.missionDiff, onSolved: onSolved);
    case 'hold':
      return HoldMission(diff: alarm.missionDiff, onSolved: onSolved);
    case 'tap':
      return TapMission(diff: alarm.missionDiff, onSolved: onSolved);
    case 'memory':
      return MemoryMission(diff: alarm.missionDiff, onSolved: onSolved);
    case 'pvt':
      return PvtMission(
          diff: alarm.missionDiff, onSolved: onSolved, onResult: onAlertness);
    case 'typing':
      return TypingMission(diff: alarm.missionDiff, onSolved: onSolved);
    case 'shake':
      return ShakeMission(diff: alarm.missionDiff, onSolved: onSolved);
    case 'qr':
      return QrMission(expected: alarm.missionData, onSolved: onSolved);
    case 'steps':
      return StepsMission(diff: alarm.missionDiff, onSolved: onSolved);
    case 'photo':
      return PhotoMission(reference: alarm.missionData, onSolved: onSolved);
    case 'eyes':
      return EyesMission(diff: alarm.missionDiff, onSolved: onSolved);
    default:
      return SlideToWake(onWake: onSolved);
  }
}
