/// The single source of truth for the free vs. premium split. Pure and tested
/// so the boundary is auditable in one place — no gating logic sprinkled ad hoc
/// through the UI.
///
/// TWO HARD RULES this encodes:
/// 1. Reliability and care are NEVER premium — the alarm firing, the Setup
///    Guardian, permission priming, the PHQ-2 check-in, and the care off-ramp
///    are always free.
/// 2. A generous free taste — basic missions, the core PVT alertness mission,
///    basic streak + weekly stats, rough-night rest, implementation intentions,
///    and a small crew — stays free so the app is genuinely useful unpaid.
enum PremiumFeature {
  // ---- Always FREE: reliability + care (rule 1) ----------------------------
  reliableAlarm,
  setupGuardian,
  permissionPriming,
  phq2Checkin,
  careOffRamp,

  // ---- Always FREE: the generous taste (rule 2) ----------------------------
  basicMissions, // math / tap / hold / memory / shake
  pvtMission, // the alertness marketing hook — a taste stays free
  singleMission, // one mission per alarm
  basicStreak,
  weeklyStats,
  roughNightExemption,
  implementationIntentions,
  basicCrew, // up to [kFreeCrewLimit] members

  // ---- PREMIUM -------------------------------------------------------------
  advancedMissions, // typing / QR / walk-it-off (steps) / photo
  missionChains, // 2–3 repeats of a mission
  adaptiveDifficulty,
  smartWakeCheck,
  alertnessHistory, // alertness history & trends
  insightsHistory,
  monthlyYearlyStats,
  shareableCard,
  unlimitedCrew,
  groups,
  voice,
  customSounds,
}

/// The features that are always free — regardless of entitlement. Everything
/// not in this set is premium.
const Set<PremiumFeature> kFreeFeatures = {
  PremiumFeature.reliableAlarm,
  PremiumFeature.setupGuardian,
  PremiumFeature.permissionPriming,
  PremiumFeature.phq2Checkin,
  PremiumFeature.careOffRamp,
  PremiumFeature.basicMissions,
  PremiumFeature.pvtMission,
  PremiumFeature.singleMission,
  PremiumFeature.basicStreak,
  PremiumFeature.weeklyStats,
  PremiumFeature.roughNightExemption,
  PremiumFeature.implementationIntentions,
  PremiumFeature.basicCrew,
};

extension PremiumFeatureX on PremiumFeature {
  bool get isFree => kFreeFeatures.contains(this);
  bool get isPremium => !isFree;
}

/// Free crew size. Adding a member beyond this needs Premium (unlimitedCrew).
const int kFreeCrewLimit = 3;

/// Free mission "chain" length. 2–3 repeats need Premium (missionChains).
const int kFreeMissionCount = 1;

/// Mission keys that require Premium. Everything else — none, math, hold, tap,
/// memory, shake, and the PVT alertness hook — is free.
const Set<String> kPremiumMissionKeys = {'typing', 'qr', 'steps'};

bool isPremiumMissionKey(String key) => kPremiumMissionKeys.contains(key);
