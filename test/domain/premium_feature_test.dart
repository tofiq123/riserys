import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/premium_feature.dart';

void main() {
  test('every feature is exactly free XOR premium (clean partition)', () {
    for (final f in PremiumFeature.values) {
      expect(f.isFree, isNot(f.isPremium), reason: '$f cannot be both');
      expect(f.isFree, kFreeFeatures.contains(f));
    }
  });

  test('HARD RULE 1: reliability and care are ALWAYS free', () {
    const mustBeFree = [
      PremiumFeature.reliableAlarm,
      PremiumFeature.setupGuardian,
      PremiumFeature.permissionPriming,
      PremiumFeature.phq2Checkin,
      PremiumFeature.careOffRamp,
    ];
    for (final f in mustBeFree) {
      expect(f.isFree, isTrue, reason: '$f must never be paywalled');
    }
  });

  test('the generous free taste stays free', () {
    for (final f in const [
      PremiumFeature.basicMissions,
      PremiumFeature.pvtMission,
      PremiumFeature.singleMission,
      PremiumFeature.basicStreak,
      PremiumFeature.weeklyStats,
      PremiumFeature.roughNightExemption,
      PremiumFeature.implementationIntentions,
      PremiumFeature.basicCrew,
    ]) {
      expect(f.isFree, isTrue, reason: '$f is part of the free taste');
    }
  });

  test('premium features are gated', () {
    for (final f in const [
      PremiumFeature.advancedMissions,
      PremiumFeature.missionChains,
      PremiumFeature.adaptiveDifficulty,
      PremiumFeature.smartWakeCheck,
      PremiumFeature.alertnessHistory,
      PremiumFeature.insightsHistory,
      PremiumFeature.monthlyYearlyStats,
      PremiumFeature.shareableCard,
      PremiumFeature.unlimitedCrew,
      PremiumFeature.groups,
      PremiumFeature.voice,
      PremiumFeature.customSounds,
    ]) {
      expect(f.isPremium, isTrue, reason: '$f is a premium feature');
    }
  });

  test('premium missions are typing/qr/steps/photo/eyes; the PVT hook and basics '
      'are free', () {
    expect(isPremiumMissionKey('typing'), isTrue);
    expect(isPremiumMissionKey('qr'), isTrue);
    expect(isPremiumMissionKey('steps'), isTrue);
    expect(isPremiumMissionKey('photo'), isTrue);
    expect(isPremiumMissionKey('eyes'), isTrue);
    for (final free in const [
      'none',
      'math',
      'tap',
      'hold',
      'memory',
      'shake',
      'pvt',
    ]) {
      expect(isPremiumMissionKey(free), isFalse, reason: '$free must be free');
    }
  });

  test('free limits are 3 crew and a single-mission chain', () {
    expect(kFreeCrewLimit, 3);
    expect(kFreeMissionCount, 1);
  });
}
