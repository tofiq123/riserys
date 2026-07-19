# Rise — Strategic Synthesis

**Date:** 2026-07-20
**Method:** 8 parallel research agents (web-enabled, cited), each on one axis — market/monetization, user sentiment, competitor teardown, sleep science, clinical/medical, behavioral psychology, wake-verification methods, real-world hacks + platform tech. This document is the cross-referenced synthesis: what the research *changes*, not a report dump. The eight raw reports live in the task outputs; the two longest (sleep science, behavioral psychology) also produced standalone artifacts.

---

## The thesis in one paragraph

The base alarm is now a commodity (Apple's AlarmKit in iOS 26 and Google Clock gave every app system-grade alarms), so Rise cannot differentiate on *ringing*. It can differentiate on three things nobody owns together: **reliability** (the single biggest unsolved user pain in the category — alarms that silently fail), **verification** (proving you're actually *alert*, not just that you tapped a button — a scientifically-grounded wedge no competitor touches), and **a known-friend accountability loop done the way the evidence says works** (shared consequence, mutual consent, layered on an alarm that already works solo). Cutting through all of it is a reframe the whole category has missed: for Rise's exact target user — "someone who genuinely can't wake up" — the honest, differentiating, and *legally safest* posture is to treat not-waking as something to understand, not a character flaw to punish. **Reliable · Verified · Kind · Together.**

---

## Part 1 — Six cross-cutting truths

These are the points where independent research axes converged. Convergence across unrelated agents is the strongest signal in the whole exercise.

### 1. Reliability is the entire game, and nobody has actually won it.
The #1 user complaint across *every* competitor is the alarm **silently not firing** — Android Doze and OEM battery-killers (Samsung deep-sleep, Xiaomi/Huawei/OnePlus autostart) sit outside AOSP's exemption model, so no single API fixes them. Meanwhile AlarmKit/Google Clock commoditized the *base* alarm. The synthesis: "wake up 100%" is not a slogan, it's an **OS-permissions engineering problem** that the whole category fails at. The most defensible single investment Rise can make is the reliability layer — the guided, OEM-aware "Setup Guardian" (already Phase 10.4) plus `setAlarmClock()` on Android and a capability-gated AlarmKit path on iOS. This is simultaneously table stakes *and* a differentiator, precisely because everyone is bad at it.

### 2. The social loop is unproven — but the design that works is now known precisely.
Every alarm app with real traction (Alarmy 75M users, Wayk, Erly) is **solo** missions/streaks with *no* crew. Every social-alarm app (UpCast, Glow Morning, Wake, SnoozeProof) is **brand-new with near-zero reviews** — the loop is commercially unproven. And the one social-wake app that ever scaled, **Wakie, abandoned waking people up entirely** (pivoted to stranger chat); Snoozle (friends'-voice-as-alarm) died outright. Both failed on the same fault: they *depended on another human firing reliably*. But adjacent evidence (Duolingo friend-streaks +22% engagement/~2.4× retention, Strava, Whoop Teams, Habitica, Forfeit's 94% completion) shows social competition *does* retain. The reconciled design spec:
- **Known friends, mutual consent** (not strangers — kills the Wakie harassment vector; the consent line is load-bearing: mutual opt-in reads as care, monitoring reads as "deranged").
- **Shared *consequence/competition*, not passive visibility** (Habitica/Forfeit retain; Glow Morning's passive "Lounge" feed has zero retention evidence).
- **Individual + group hybrid, not team pass/fail** (Kullgren 2016 RCT: pure team incentives didn't beat control; individual+group combined nearly doubled it. Milkman 2024: a reward paid only when you show up *with* a friend drove +35% gym visits).
- **Upside on a solo alarm that already works** (so the product survives an inactive friend — the anti-Wakie).

### 3. Missions are commoditized. The innovation is *scientific verification*, not more missions.
No-code app factories now spit out math/shake/QR missions; "mission variety is no longer a moat." Worse, missions **decay** — real user quotes: *"I learned to do the math without waking up, then learned to delete the app without waking up."* The genuinely novel wedge, confirmed absent from every competitor across 10+ searches, is **post-dismissal verification that you *stayed* awake and a measure of *how* awake you are.** Three buildable pieces:
- A **mini-PVT mission** (Psychomotor Vigilance Task — the sleep field's gold-standard alertness measure; PVT-B is a NASA-validated 3-min version, ~355 ms lapse threshold). Adapted to ~60–90s it's a dismissal gate that *also* outputs a real alertness number. Pure Flutter, no permissions. **No alarm app on earth does this.**
- A **sustained-motion consensus** check (5–10 min of walking via activity-recognition, not one shake) — kills the "shook it and lay back down" loophole; low battery, low creepiness.
- A **multi-signal awake-confidence score** fusing motion + app-interaction + optional light/camera/PVT into a probability, with a graceful re-ring when confidence is low (not a silent accusation — heeding Sleep as Android's "if you can't make it 100%, don't do it" warning).

### 4. The medical reframe is the deepest differentiator — and the biggest trap.
Rise's target user ("can't wake up") is *statistically the population most likely to have an undiagnosed medical disorder*: Delayed Sleep-Wake Phase Disorder runs **7–16% in teens/young adults**, plus idiopathic hypersomnia, sleep apnea, and depression-hypersomnia. This is Rise's single biggest asset (a real, ownable hook no competitor touches) and its single biggest liability (streak-shame mechanics will, by construction, punish some users for a medical condition). Rise can be the *only* alarm that treats not-waking as potentially clinical, not moral — via a **consistent fixed wake-time engine** (the one CBT-I/circadian lever a wake app natively owns), a **PHQ-2 pre-screen** (2 questions, public domain, free), and a **"patterns worth seeing a doctor about" off-ramp that is never gated behind streaks.** This is ethical high ground, a differentiator, a trust/retention play, *and* a liability shield — all at once.

### 5. Shame is the central product tension, and it must be engineered around.
Hard-to-wake people describe deep **shame** — "not laziness, an invisible disability" — and oversleeping that damages relationships. That's a positioning goldmine ("this isn't a willpower problem") *and* a landmine (a "prove you're awake / you failed, everyone sees" framing re-triggers the shame and, per peer-reviewed gamification-harm literature, causes "a strong sense of defeat" and can deter care-seeking). The razor's edge: **accountability motivates; shame harms** (and creates liability). Every tone decision flows from this — "protect your crew" (warm, pro-social) beats "you let everyone down" (shame). A medical/rough-night **streak-freeze exemption** is not a nicety; it's ethically required *and* a proven retention feature (Duolingo).

### 6. The no-snooze orthodoxy is wrong.
55.6% of alarm sessions end in snooze (Nature, 3M sessions). And the science says **one snooze is roughly harmless and may modestly *help* early cognition/mood** — harm concentrates in *repeated* snoozing. So the evidence-backed design is not "no-snooze purity" but **one free verified snooze, then earn further snoozes via a mission.** This aligns science, real behavior, and reduced over-punitive-design rage in one move.

---

## Part 2 — The repositioning: Reliable · Verified · Kind · Together

The research collectively argues for tightening the positioning from a generic "wake up 100%, socially accountable" into four evidence-backed pillars:

| Pillar | What it means | Why it's defensible |
|---|---|---|
| **Reliable** | The alarm fires, every time, through Doze/Focus/OEM-killers. Guided Setup Guardian. | #1 unsolved pain; commoditized base alarm means this is where trust is won or lost. |
| **Verified** | Proves you're *alert*, not just awake. Alertness score + confidence engine. | Scientifically grounded (PVT), genuinely novel, un-cheatable by habit — the real moat. |
| **Kind** | Treats not-waking as understandable, not a moral failure. Medical-aware, anti-shame, care off-ramp. | Nobody does it; ethical high ground; trust/retention; liability shield. |
| **Together** | Known-crew shared-consequence accountability, layered on a solo alarm that works. | Evidence-backed social design; the anti-Wakie; the retention engine done right. |

Marketing line candidate: *"The alarm that actually gets you up — and measures how awake you really are."* (Honest: PVT measures reaction-time alertness, a validated proxy — **not** sleep stage, which phones cannot detect and which we must never claim.)

---

## Part 3 — Novel digitizable ideas, ranked

Ranked by (impact × evidence × feasibility on Rise's stack). Each ties to a specific research finding and a gap in a named competitor.

1. **The Alertness Score (mini-PVT mission).** *Flagship.* A ~60–90s randomized-ISI reaction-time task that dismisses the alarm *and* produces a real alertness number that feeds streaks/insights ("your alertness is ~40% lower on 5-hour nights"). Scientifically defensible (Dinges PVT-B), un-fakeable by habit, pure Flutter/no-permissions, **zero competitor precedent.** *Marketing wedge nobody can copy quickly.*

2. **The Wake-Confidence Engine.** Fuse sustained-motion + Rise's own app-interaction events + optional light/camera/PVT into a post-dismissal probability you're actually up; graceful re-ring on low confidence. The strategic core — no competitor does passive post-dismissal fusion. Start with signals Rise already controls (motion + app events).

3. **Consistent-wake-time + gradual-shift engine.** The single clinically-validated (CBT-I/circadian) lever a wake app owns outright (scored 15/15 in the clinical review). Anchor a fixed wake time; optionally shift it gradually toward a goal. Frame as "building a rhythm," never as "treating a disorder."

4. **Implementation-intentions onboarding.** One screen: *"When my alarm rings, I will ______"* (pick/write a concrete first action — feet on floor, walk to kitchen). d=0.65 across 94 studies — the cheapest high-leverage feature in the entire review. Pure UI.

5. **The gentle "is this medical?" screener + care off-ramp.** Optional, non-diagnostic. Recognizes discriminating patterns (sleep fine on free days but can't wake on workdays → DSWPD; 10h+ still unrefreshed → IH/OSA/depression) and PHQ-2 (free) → surfaces "worth talking to a clinician," never a label. Duty-of-care + differentiator + liability shield.

6. **Shared-consequence crew.** Streak-break notifies/affects the crew (consequence, not passive feed); reward-with-a-friend mechanics; individual+group hybrid scoring. This is the evidence-backed version of the social layer already at design stage.

7. **Sustained-motion "stay up" check (5–10 min).** Extends the existing Phase 4b wake-check from a single prompt to a low-battery activity-recognition consensus. Kills the "got up, got back into bed" failure.

8. **Adaptive mission difficulty.** Missions that escalate as the user gets good at cheating them (harder math tiers, mission chains, rotating server-side QR codes) — directly answers the "missions decay" complaint.

9. **Camera eye-openness mission (PERCLOS).** Best-supported genuinely-new *active* mission; on-device ML Kit (Android) / Vision (iOS), no cloud — clean privacy story. Enforce liveness to block photo-spoofing.

10. **Stakes Mode (v2).** Real commitment device (Forfeit: 94% completion), but **ethical** — forfeited stakes go to charity or the crew pot, *never* to Rise (MoneyAlarm keeps them itself — a conflict of interest to avoid). Deferred for payments/legal overhead.

**Your specific hypothesis — "left home = awake" via location:** the research verdict is **don't build passive background geofencing** (Play/Apple policy risk — an alarm has no qualifying justification for background location; plus creepiness, plus it structurally fails for WFH/shower/weekend users). But an **optional foreground "walk N steps / N meters" mission** while the alarm is ringing is fine and achieves the same "out of bed" effect (NeuroAlarm does exactly this). So: the instinct (physical displacement = awake) is right; the *passive-tracking* implementation is the part to drop.

---

## Part 4 — What the research kills

Things we might have built on reflex that the evidence says **don't**:

- **Don't claim "smart alarm wakes you in your lightest sleep."** Unproven in controlled trials; phones physically cannot detect sleep stage (0 of 4 tested apps could even detect REM). If ever shipped, frame as "may help some mornings" with a *hard-deadline fallback alarm*.
- **Don't rely on the phone screen as a wake light.** ~30–110 melanopic lux vs. the ~250+ needed for real circadian/alertness effect — biologically ≈ doing nothing. The honest feature is a *prompt to get real light* (open a window / go outside), or a smart-bulb integration.
- **Don't build "no-snooze" purity.** (See Truth 6.)
- **Don't do passive background geofencing / background microphone / wearable real-time gating.** Policy risk, creepiness, and (for wearables) sync latency that makes real-time verification impossible today. Wearables are corroboration/analytics only.
- **Don't lean on debunked pop-psych.** Purge "21 days to a habit" (it's ~66-day median), the "5-second rule" (zero peer-reviewed backing), and "identity-based habits" framing (the real science — Bem's self-perception — runs the other way: *behavior* shapes identity, so reward the *action*, not the self-label).
- **Don't overclaim biometrics.** FDA precedent (the WHOOP warning letter over color-coded blood-pressure) shows *marketing language and UI framing* trigger device status. Rise's stats screen and any "sleep score" are part of its regulatory surface.

---

## Part 5 — Medical / ethical guardrails (non-negotiable)

Rise stays a "general wellness" product (outside FDA device regulation / EU MDR) only by discipline. The consolidated red lines:

- **Never** say Rise diagnoses / treats / cures / prevents any disorder (insomnia, DSWPD, apnea, hypersomnia, depression), and **never** tell a user they have — or don't have — a condition.
- **Never** label data/scores "abnormal," "pathological," or reference clinical thresholds (the WHOOP trigger).
- **Never** call a feature "CBT-I" or claim equivalence to cleared products (Somryst/SleepioRx).
- **Never** auto-generate a personalized melatonin dose/time or a light-therapy lux protocol; **never** automate sleep restriction or chronotherapy (documented harm — can induce Non-24).
- **Never** let a "smart wake" window replace a guaranteed fallback alarm.
- **Never** deploy shame/guilt mechanics; **never** let streak-preservation override a health/rough-night exemption; **never** gate or suppress the "see a doctor" off-ramp for retention.
- **Never** embed licensed screeners (ESS, MEQ, MCTQ, STOP-BANG) without a license. PHQ-2/9 is public domain and safe.
- Positioning/disclaimer template to copy: the VA's **Insomnia Coach** ("stand-alone education and self-care tool… not intended to replace needed professional care," with contraindication flags), *not* the prescription-grade Somryst.

The reassuring part: caution and helpfulness point the same way here. The honest posture (modest claims, hard fallbacks, route-to-care) is also the legally safest one.

---

## Part 6 — How this re-orders the roadmap

The existing roadmap (`roadmap-2026-07-20.md`, Phases 6–12) is still sound as a *feature* list. The research changes the *priority ordering* and adds a few net-new items:

**Elevated / net-new (do earlier):**
- **Reliability layer first** (Setup Guardian + `setAlarmClock()` audit + OEM allowlist onboarding). Roadmap 10.4 — promote toward the front; it's the #1 pain and the trust foundation.
- **Alertness Score / mini-PVT mission** — net-new; the flagship differentiator. Slots into the Phase 6 mission framework; pure Dart, fully buildable on Windows.
- **Wake-confidence engine + sustained-motion consensus** — net-new; extends Phase 4b wake-check. Needs `activity_recognition_flutter` + a device pass.
- **Implementation-intentions onboarding screen** — net-new; trivial, high-leverage. Folds into Phase 10 onboarding.
- **Anti-shame tone pass + medical/rough-night streak-freeze** — net-new; touches Phase 9 (stats/streaks) copy and mechanics. Cheap, ethically required.

**Adjusted:**
- **Missions (Phase 6):** reframe from "more missions" to "adaptive + verified" — adaptive difficulty, mission chains, rotating server-side QR, PVT. Copy Alarmy's "Wake-Up Check" (Rise already has the wake-check primitive).
- **Monetization (Phase 11):** the category defaults to a 7-day trial, but if Rise is categorized **Lifestyle** (where alarm apps usually sit), trials *cut* Year-1 LTV by ~21% — strongly consider a **hard paywall / direct-buy at $5–7/mo + a lifetime tier**, undercutting Alarmy's monetization resentment. Anchors: ~40% trial→paid (top decile 68%), ~$30 median annual price, 67% of health subs annual.
- **Stats (Phase 9):** becomes the surface for the Alertness Score, honest insights, and the PHQ-2/care off-ramp — but every number must pass the "not-a-diagnosis, not-abnormal" copy test.

**New cross-cutting items (not a phase):**
- **Name/trademark decision** — "Rise" is badly crowded (RISE Science, 10M+ users, Apple Editors' Choice; plus existing "Rise Alarm Clock" and "RiseDaily – Streak Alarm"). Live ASO/trademark collision; resolve a differentiated name/suffix before any paid acquisition.
- **iOS AlarmKit spike** — AlarmKit pierces Silent/Focus but gives **no callback when the user swipes the alarm away**, so mission-gating can't hook dismissal through it; needs a companion foreground flow. Spike before committing the iOS 26 path.
- **Distribution: TikTok UGC** — the category's proven channel (Wayk: 25M views → #15 App Store → 100K downloads in 30 days; Reddit/Product Hunt gave nothing). Crew drama / leaderboard call-outs are a *better* native TikTok story than a solo alarm.

---

## Part 7 — Open decisions for you

These are genuine forks the research surfaced but can't decide:

1. **Name.** Keep "Rise" and accept the ASO/trademark collision, or pick a differentiated name/suffix now? (Recommendation: decide before spending on acquisition.)
2. **How far into the medical angle?** From "light touch" (anti-shame tone + streak-freeze only) → "screener" (add PHQ-2 + care off-ramp) → "rhythm engine" (add consistent-wake-time + gradual-shift). More depth = more differentiation *and* more discipline/liability surface.
3. **Pricing model.** Hard paywall (Lifestyle-category data favors it) vs. the category-standard free trial? And a lifetime tier yes/no?
4. **Where the flagship goes first.** Alertness Score (novel, Windows-buildable, marketing wedge) vs. reliability layer (biggest pain, trust foundation) as the *next* build. (They're complementary; the question is sequence.)

---

*Sourcing note: factual claims above trace to the eight agent reports. Highest-confidence items were directly verified against primary sources (RevenueCat/Adapty benchmarks; FDA General Wellness guidance + WHOOP letter; AASM DSWPD guideline; Gollwitzer/Sheeran, Lally, Milkman, Kullgren; Basner PVT-B; Fino 2020 smart-alarm validation). Explicitly discard: all "sleep app market size" dollar figures (sources disagree ~4×) and the convenient-but-unverified "social features → 20–35% lower churn" stat.*
