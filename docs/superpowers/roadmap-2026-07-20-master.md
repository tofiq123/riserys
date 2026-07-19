# Rise — Master Roadmap (research-driven)

**Date:** 2026-07-20 · **Supersedes:** `roadmap-2026-07-20.md` (folds its Phases 6–12 into this pillar structure and reprioritizes per the 8-agent research). **Strategy basis:** `docs/superpowers/research/2026-07-20-strategic-synthesis.md`.

## What changed
The base alarm is commoditized (AlarmKit/Google Clock). Rise differentiates on four evidence-backed pillars — **Reliable · Verified · Kind · Together** — not on having more features. This roadmap sequences *everything* from here to launch, ordered by (value × how much I can finish + verify on this Windows machine), so momentum never waits on a device, a Mac, or your accounts.

## The four decisions (made on your behalf — each reversible, veto any)
1. **Name:** keep "Rise" as the working name through the build; it blocks nothing. Resolve a differentiated public name + trademark screen **before paid marketing** (Phase 19), not before engineering. ("Rise" collides with RISE Science, 10M+ users, and RiseDaily-Streak Alarm.)
2. **Medical depth: full, but phased** — tone-first (Phase 7), screener + rhythm engine (Phase 8). Maximum differentiation with the discipline the regulatory red lines demand.
3. **Pricing: freemium with a hard paywall (no timed trial) + a lifetime tier.** The reliable alarm + basic missions stay free (you can't paywall "the alarm works"); premium gates advanced missions, insights, voice, groups. Lifestyle-category data shows trials *cut* Year-1 LTV ~21%. (Phase 17.)
4. **Flagship first:** build the **Alertness Engine (Phase 6)** now — it's the unique marketing wedge and fully buildable/testable here. The reliability layer (Phase 12) is co-priority but device-gated, so it lands the moment a phone is connected.

## Legend (how far I take each item on Windows)
✅ **full** — Dart/UI, built + unit/widget-tested to green here · 🔶 **build-verified** — compiles + reviewed here, real behavior needs wired backend · 📱 **device** — needs an on-device pass · 🔑 **accounts** — needs your Supabase Storage / RevenueCat / store setup · 🍎 **Mac** — iOS compile pass first.

## Where we are (done + merged to main)
Plans 1–3 (alarm core + UI), Phase 4a (wake data/streaks), 4b (snooze/wake-check), 5a–5e (auth, crew, live status, leaderboard, push/nudges), iOS engine (written, needs Mac compile). 350 tests green.

---

# The build sequence

Pillars tag each phase; the numbers are the **linear build order**. Windows-buildable phases come first so I ship verified work continuously; device/account/Mac phases are sequenced for when those unlock (and flagged, not deprioritized).

## Phase 6 — Alertness Engine (mini-PVT)  · VERIFIED · ✅ · **flagship, building now**
The wedge no competitor has. A ~60–90s Psychomotor Vigilance Task (PVT-B-derived: randomized inter-stimulus interval, ~355 ms lapse threshold) that dismisses the alarm **and** outputs a real alertness score (0–100). Persists to the wake event; surfaces an honest trend in Stats ("reaction-speed alertness — not a medical measure").
- 6.1 PVT engine (pure Dart: randomized ISI, lapse/false-start detection, metrics) ✅
- 6.2 Alertness scoring function (metrics → 0–100) ✅
- 6.3 PVT mission widget (plugs into `mission_host`) ✅
- 6.4 Register `'pvt'` in Create/Edit picker + labels ✅
- 6.5 Persist `alertnessScore` (WakeEvent + Drift column + migration + recorder) ✅
- 6.6 Stats surface: latest + average + trend, honest copy ✅
*Plan: `docs/superpowers/plans/2026-07-20-phase6-alertness-engine.md`.*

## Phase 7 — Compassion & Intentions  · KIND · ✅ · **cheap, high-leverage, next**
The anti-shame foundation must exist before we lean harder on streaks/crew. All pure Dart.
- 7.1 Anti-shame tone pass (copy audit across ring/stats/streak: "protect your crew" not "you failed"; remove guilt language).
- 7.2 Streak-freeze / rough-night exemption ("mark last night rough" pauses the streak without penalty — Duolingo's proven retention lever *and* an ethical requirement).
- 7.3 Implementation-intentions onboarding — one screen, *"When my alarm rings, I will ___"* (d=0.65 across 94 studies).
- 7.4 Permission-priming copy ("why we ask") rewrite for higher grant rates.

## Phase 8 — Rhythm & Care  · KIND · ✅ (📱 for reminders)
The clinically-grounded core, framed as wellness, never treatment.
- 8.1 Consistent-wake-time anchor (a target wake time; gentle nudges toward it) — the one CBT-I lever a wake app owns (15/15 clinical).
- 8.2 Gradual wake-time-shift scheduler (small daily increments toward a goal wake time; habit-framing).
- 8.3 PHQ-2 pre-screen (2 items, public domain) → "patterns worth seeing a doctor about" off-ramp, **never gated behind streaks**.
- 8.4 Honest insights (weekday/weekend patterns; consistency) — all pass the not-a-diagnosis / not-"abnormal" copy test.
- 8.5 Bedtime reminders 📱 (nudge to sleep in time to hit the wake goal).

## Phase 9 — Missions Overhaul  · VERIFIED · ✅ + 📱
Reframe from "more missions" to "adaptive + verified" (missions decay; variety is no longer a moat).
- 9.1 Adaptive difficulty + mission chains (require 2 in a row; escalate as the user gets good at cheating) ✅
- 9.2 Math tiers + typing mission ✅
- 9.3 Shake mission 📱 (`sensors_plus`)
- 9.4 QR/barcode mission 📱 (`mobile_scanner`; rotating server-side codes for anti-cheat)
- 9.5 Photo-match mission 📱 (`camera`/`image_picker`)
- 9.6 Steps/walk mission 📱 (`pedometer`) — also the honest, policy-safe version of your "left home = awake" idea
- 9.7 PERCLOS camera eye-openness mission 📱 (ML Kit / Vision; on-device, liveness-guarded)

## Phase 10 — Ringtones & Sensory Wake  · RELIABLE · 📱
- 10.1 Real CC0 sound library (gentle→aggressive; the 5 slots are placeholders today) + per-alarm selection wired end-to-end.
- 10.2 Volume fade-in + vibration patterns; low/mixed-frequency tones (evidence: wake more reliably).
- 10.3 On-screen sunrise + flashlight strobe (<3 Hz, seizure disclaimer).
- 10.4 "Get real light" prompt (phone screen is too dim to wake you biologically — prompt to open a window / go outside).

## Phase 11 — Wake-Confidence & Stay-Up  · VERIFIED · 📱
Extends Phase 4b's wake-check into passive verification nobody does.
- 11.1 Sustained-motion consensus (5–10 min activity-recognition window — `activity_recognition_flutter`/`pedometer`) — kills "shook it and lay back down".
- 11.2 Multi-signal awake-confidence score (motion + app-interaction + optional light/PVT) with graceful re-ring on low confidence (frame as confidence, never accusation).

## Phase 12 — Reliability & Setup Guardian  · RELIABLE · flow ✅ / checks 📱 · **co-priority; the moment a device is on**
The #1 unsolved pain in the whole category.
- 12.1 OEM battery-killer allowlist onboarding (dontkillmyapp-style, per-manufacturer).
- 12.2 Android `setAlarmClock()` audit (the one Doze-exempt path) + full-screen-intent grant fallback.
- 12.3 Setup Guardian screen (checks battery optimization, notification channels, exact-alarm, OEM settings; walks the user to fix each).
- 12.4 First-alarm wizard + sleep-goal setup.

## Phase 13 — Stats, Insights & Achievements  · GROW · ✅
- 13.1 Achievements/badges (7/30/100-day, early bird, perfect week, no-snooze) — reward the *action*, not a self-label (the science).
- 13.2 Trends & consistency score; alertness trends (from Phase 6).
- 13.3 Shareable stats card 📱 (the TikTok viral loop — the category's proven channel).
- 13.4 Monthly/yearly views.

## Phase 14 — Crew Depth & Consequence  · TOGETHER · 🔶🔑
The retention engine — done the way the evidence says (consequence, not passive visibility).
- 14.1 Shared-consequence streaks (crew notified/affected on a break) — the piece with retention evidence.
- 14.2 Reward-with-a-friend + individual+group hybrid scoring (pure team pass/fail does *not* beat control; hybrid nearly doubles it).
- 14.3 Friend detail screen (streak, on-time %, live status, mutual stats).
- 14.4 Activity feed + reactions ("Ada woke on time 🔥").

## Phase 15 — Groups & Challenges  · TOGETHER · 🔶🔑
- 15.1 Named groups + RLS; 15.2 group leaderboards + challenges ("everyone wakes by 7am for 7 days"); 15.3 invite deep links (`rise://invite/<code>`) 📱.

## Phase 16 — Voice Wake-ups  · TOGETHER · 📱🔑
Record a clip (`record`) → Storage+RLS → playback (`just_audio`) → send-to-crew (or set as their alarm sound — a "voice alarm gift") → inbox.

## Phase 17 — Monetization  · GROW · 🔑
RevenueCat; free/premium split (free: reliable alarm + basic missions + small crew; premium: advanced/verified missions, insights, voice, groups, custom sounds); **hard paywall (no trial) at ~$4.99/mo or ~$39.99/yr + lifetime tier**; purchase/restore + gating.

## Phase 18 — Polish & Platform  · GROW · mixed
Launcher icon + splash ✅; dark mode ✅; home-screen widget 🔶📱; localization/a11y ✅; optional smart-home wake (Philips Hue bridge ramp, server-triggered) 🔑.

## Phase 19 — Launch Readiness  · GROW · external
Name/trademark decision + ASO; TikTok UGC kit; store listings; **iOS Mac compile pass** 🍎; multi-day reliability soak 📱; the 2-account/2-device social validations (crew/status/leaderboard/nudge).

---

## Cross-cutting tracks (run alongside, not phases)
- 🍎 **iOS Mac compile-and-fix pass** (`docs/superpowers/reliability/2026-07-20-ios-compile-checklist.md`) — unblocks every device feature's iOS side. Also spike **AlarmKit's no-dismissal-callback** gap (mission-gating needs a companion foreground flow).
- 📱 **Deferred device validations backlog** — wake-check pass; 2-account crew/status/leaderboard/nudge; then each new 📱 mission/sensor as the phone is free.
- 📈 **Distribution** — TikTok UGC is the category's proven channel (crew drama > solo alarm); seed 2–3-person crews + inviter reward + graceful streak-freeze.

## Immediate order I'll build (Windows-verifiable, no waiting)
**6 → 7 → 8 → 9.1/9.2 → 13** (all mostly ✅), interleaving the 📱/🔑 phases (10, 11, 12, 14–19) as the phone/accounts/Mac unlock. Phase 6 starts now.
