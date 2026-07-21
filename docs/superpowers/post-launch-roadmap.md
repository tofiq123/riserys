# Rise — Post-launch roadmap

**Date:** 2026-07-21. Where the deferred pre-launch items land, plus the growth work the 8-agent research points to (see `research/2026-07-20-strategic-synthesis.md`). Sequenced as focused pushes, not simultaneous. Live dashboard: the "Rise — Status & Roadmap" artifact.

Pre-launch build queue (must finish first): 24h time ✅ · mission cleanup · Sound & Ring (ringtones + vibration + voice-as-alarm) · dark mode.

---

## L1 · Land it
Store launch. Resolve the **name/trademark** (the "Rise"/RISE Science collision — do before paid acquisition), ASO, store listings, a real **release keystore** (+ register its SHA-1 for Google sign-in). Crash reporting (Crashlytics/Sentry) and — most important — instrumentation for the **"alarm didn't fire"** signal (the category's #1 churn driver). Onboarding-funnel analytics. Fast hotfix cadence.

## L2 · Make them stay
Retention is brutal here (~5–7% D30); crew + streaks is the proven lever. Lifecycle notifications: **bedtime reminders** (deferred Phase 8.5), streak-at-risk, crew nudges. Streak-freeze/repair tuning. Win-back / re-engagement flows. The PHQ-2 care off-ramp as a trust asset. D1/D7/D30 cohort dashboards.

## L3 · Grow it
**TikTok UGC engine** — the category's proven channel (a rival hit 25M views → #15 App Store; Reddit/PH gave nothing). Crew virality: **deep-link invites** (deferred), inviter rewards, 2–3-person crew seeding. Activity feed → shareable wins. Referral loop. Continuous ASO.

## L4 · Earn from it
RevenueCat experiments: hard-paywall vs free-trial **by cohort** (Lifestyle-category data says trials cut LTV), price points, the lifetime tier. Premium-surface tuning, win-back offers, LTV/ARPU dashboards.

## L5 · Everywhere
**iOS full launch** — the Mac compile-and-fix pass (`reliability/2026-07-20-ios-compile-checklist.md`) + **AlarmKit** for iOS 26 (with the no-dismissal-callback spike). **Apple Watch / Wear OS** silent haptic alarm (a real differentiator — native companions). **Home-screen widget** (next alarm + streak). **HealthKit / Google Fit** + wearable corroboration (analytics, not a real-time gate). Smart-home wake (Philips Hue bridge ramp, server-triggered).

## L6 · The moat
Mature the **Wake-Confidence Engine** — add the native "cancel wake-check" so smart-wake can become the default (closes the opt-in deferred-arm gap). Market the **mini-PVT alertness science** (alertness trends/insights). Deepen the **Kind** layer: chronotype personalization, consistent-wake-time coaching, careful "worth seeing a doctor" screening (within wellness bounds — never diagnose). Social depth: **group challenges**, seasons/leagues (Duolingo model), server streak-break fan-out + custom push copy, voice-as-alarm gifts.

## L7 · Scale & reach
Full **localization** (the l10n string migration + languages) with **localized care helplines** per region. Regional pricing. Backend/RLS perf + cost hardening. **Content moderation** for the social feed + voice clips (trust & safety).

## L8 · The science flywheel
Anonymized aggregate wake/alertness data → product insights + **"science of waking"** marketing. An experimentation/A-B platform. Explore partnerships (sleep/wellness) or a **B2B employer-wellness** angle.

---

### Deferred pre-launch items → their post-launch home
home-screen widget → L5 · HealthKit/Fit → L5 · bedtime reminders → L2 · group challenges + fan-out + deep-links → L3/L6 · iOS → L5 · launch prep → L1 · smart-home → L5 · full l10n → L7.
Held back because each needs the store, a Mac, scale, or live data — not forgotten.
