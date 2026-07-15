# Rise — Social Alarm App: Design Specification

**Date:** 2026-07-15
**Status:** Approved section-by-section in brainstorming; pending final user review
**Source design:** `project/Rise.dc.html` (Claude Design handoff bundle) + `project/design_handoff_rise_alarm/README.md`

---

## 1. Product definition

Rise is a social alarm app for iOS and Android. Its promise: get users **out of bed** — not just past the alarm — and make waking up something you do *with* your friends.

"Wake users 100%" is delivered as a layered defense, each layer grounded in research:

1. Sound engineered to actually wake humans (low-frequency, melodic, ramping)
2. Escalating multi-sensory pressure (sound + vibration + screen light)
3. Missions that force cognition/movement before the alarm ends
4. Social accountability as the final backstop (crew nudges when you sleep through)

### Decisions locked during brainstorming

| Decision | Choice |
|---|---|
| V1 scope | Full social app (accounts, crew, live status, voice alarms, leaderboard) |
| Monetization | Freemium from day 1 ("Rise Plus" subscription, monthly/annual + trial) |
| Auth & friend graph | Sign in with Apple + Google; friends via invite links + usernames. No phone auth in v1 |
| Sleep data | Inferred (bedtime reminder → dismissal) + HealthKit / Health Connect read |
| Finish line | Public launch on App Store + Play Store |
| Stack | Flutter + custom native alarm modules (Swift/Kotlin) + Supabase + RevenueCat + Codemagic (iOS cloud builds) + Shorebird (OTA patches) |

### Product principles (evidence-based)

1. **Consistency is the hero metric.** Wake-time regularity is the best-evidenced sleep lever (UK Biobank, n=60,977: top-quintile sleep regularity → ~30–48% lower all-cause mortality; regularity predicts mortality better than duration). The streak counts *waking on time at a consistent hour*, not app opens.
2. **Sound that actually wakes people.** Defaults built on ~520 Hz low-frequency, melodic, gradually ramping audio (low-frequency signals wake 4–12× better than high-pitched tones and survive age-related hearing loss; melodic tones reduce perceived sleep inertia). Sound rotation offered as an anti-habituation hedge, honestly framed ("keeps your alarm from getting stale," not "scientifically proven").
3. **Multi-sensory escalation.** Haptics wake ~95–100% in studies; stacking sound + vibration + light is the robust path to "100%".
4. **Snooze is managed, not shamed.** Bounded ~30 min snoozing isn't clearly harmful (Sundelin 2023). Rise uses a *snooze budget*: configurable count with shrinking durations (9→5→3 min), then mission required. Anti-snooze framing is behavioral ("up by 6:00 for your run"), never health-scare. ~56% of alarm sessions end in snooze — snoozers ARE the market; shaming them misfires.
5. **Streaks with forgiveness.** Streak freezes (earned 1/week of consistency) increase retention (Duolingo-scale evidence). Missing a day doesn't kill the habit — quitting after the miss does.
6. **Competition sustains behavior better than support** (STEP UP RCT). Crew leaderboard is central; accountability framed around actions ("up by 6:00"), not identity ("morning person").
7. **Safety and compassion built in.** Gentle mode for clinical/shift-work users; a safety escape on every mission; no medical overclaiming. **No "smart wake windows" in v1** — consumer sleep-stage detection is ~60–85% accurate and the one controlled test showed no benefit.
8. **Honest marketing.** We never claim to prevent uninstall/force-quit (nobody can). Social cost + streak loss is the enforcement mechanism.

---

## 2. Feature map

### V1 — Free tier

**Alarm core**
- Alarms: create/edit/delete; time; repeat days; label; sound; per-alarm mission + difficulty; snooze policy; vibration pattern
- Reliability engine (§4): rings through silent, DND/Focus, reboots, app kills
- Ringing screen: slide-to-wake, structured snooze (budget shown live), voice-alarm attribution chip
- Missions: **Math, Hold, Tap, Memory** (per prototype) + **Typing** (retype phrase) + **Shake** (movement) + **Photo** (re-shoot a registered spot) + **QR/Barcode** (scan a registered code). All 8 free at Easy/Medium; Hard is Plus
  - *Photo/QR are the only missions that physically remove you from bed — every prototype mission is completable under the duvet. This is the category's most-praised mission type (Alarmy, I Can't Wake Up!, Sleep as Android, Nuj) and was pulled into v1 on that evidence. Photo matching is on-device (perceptual hash vs registered reference); no image leaves the phone.*
- **Wake-up check** (free, including all its timing controls — Alarmy paywalls this): "Still up?" notification **5 min after dismissal (configurable 1–30, default on)**; unanswered within **100 s** → alarm re-fires with the alarm's mission. *Dismissing the alarm isn't the failure mode; falling back asleep is. Also covers iOS AlarmKit's lack of a swipe-dismiss callback (§4).*
- **Goal-locking:** alarm time locks 4 h before it fires — no 2 a.m. "just move it to 9" edits. Prevents the cheat that makes streaks and leaderboards meaningless. Overridable in Gentle mode; emergency unlock costs the streak.
- Setup Guardian: permission/volume/battery-exemption checklist with per-OEM guidance + **Test my alarm** button; re-validates on every launch
- Bedtime reminder with wind-down notification; **mid-night battery alarm** (if projected charge won't survive to wake time, wake the user to plug in)
- 3 active alarms max (free)

**Social (free — network effects are never paywalled)**
- Accounts: Apple/Google sign-in, unique username, colored-initials avatar
- Crew: add via invite link or username; live status (asleep/waking/awake) with countdowns; nudges (high-priority push)
- 1 group (free); group alarms ("Wake the group") + Nudge all
- **Voice alarms**: record ≤15 s → becomes friend's alarm sound. Free forever (viral core). Consent model below
- Streak leaderboard among crew
- **Social escalation** (opt-in, off by default): alarm ringing/re-ringing unacknowledged for **10 min** → push to crew: "Alex isn't waking up — nudge them". The last rung of the escalation ladder and the one no competitor can copy without a social graph

**Stats (basic free)**
- Wake consistency score (hero), current/best streak, estimated sleep duration, 7-night chart, snooze counts, wake-vs-set delta
- Sleep estimate = bedtime-reminder-ack → first dismissal, refined by HealthKit/Health Connect samples when present

### V1 — Rise Plus (subscription)

- Unlimited alarms
- Hard mission difficulties + **mission chaining** (2–5 missions per alarm, e.g. math → photo); chain difficulty multiplies leaderboard scoring
- Unlimited groups
- Full stats history + trends, sleep-debt analysis (free: last 7 days)
- Custom alarm sounds (upload/record own), premium soundscapes, sound rotation
- Dawn-simulation screen ramp (final 30 min; marketed as "feel less groggy" — subjective-alertness evidence only)
- Extra streak freezes (5 vs 2); custom app icons

### Deferred to v1.1+

Wearable/watch apps; home/lock-screen widgets; money-stake "hard mode" (potent but low uptake — opt-in only, and gambling-adjacent legal diligence needed first); "ping a friend to record tomorrow's alarm" two-sided loop (YouUp's mechanic — strong, but v1 proves delivery first); morning feed with reactions; nap timer; in-app sleep-stage tracking; midnight dark theme (prototype's hidden second theme — deliberate cut from v1); localization beyond English.

### Competitive position

*(full evidence: `../research/2026-07-15-competitor-research.md`)*

**The whitespace is real but no longer empty.** No shipping app combines missions + wake-check + friend voice alarms + live status + leaderboards. Alarmy (110M+ downloads, ~$33M revenue) has enforcement without social. Galarm has group alarms without enforcement. Wayk/Erly have streaks without friends. **However, Apple's AlarmKit (iOS 26) triggered a wave of direct competitors in the last year: Wake: The Social Alarm (friend voice alarms + group alarms + feed), YouUp, NOX (friend video alarms), Alarm Friend.** None has traction yet — this is a speed race, not an empty field.

**Rise's defensible claim:** *when the OS fails, your Crew doesn't.* Human backup is the one reliability layer only a social alarm app can offer. Every competitor's reliability story ends at the OS boundary.

**Category lessons applied:**
- Every dead competitor (Kiwake, Walk Me Up, Step Out!, Mimicker, I Can't Wake Up!) died of the same two diseases: **OS updates breaking background hacks, and abandonment.** Reliability engineering is the moat, not mission creativity — hence §4's weight and the launch gate in §9.
- Galarm's top complaint is **alarms 30+ min late / recurring alarms silently failing** — social sync added a server dependency to a must-never-fail local system. Hence: local DB is the source of truth; **no alarm ever depends on a network call** (§3).
- Alarmy's #1 churn theme is **battery drain**; #2 is paywall aggression ("used to be $2 one-time"). Hence: no overnight keep-alive on modern iOS, no ad-to-snooze ever, and enforcement/reliability free forever (§7).

**Naming risk (flagged for decision, outside this spec):** at least four unrelated "Rise" alarm apps exist on the stores (none social). Expect App Store search collision; trademark diligence recommended before launch.

---

## 3. Architecture overview

### Flutter app (single codebase, Dart)

```
lib/
  ui/          Screens + design system (mono theme tokens from prototype,
               Geist + Geist Mono bundled; components: Card, PrimaryButton,
               Switch, SegmentedControl, TimeDial, DayChips, AvatarStack,
               StatusDot, SlideToWake, MissionWidgets, Toast, Paywall)
  state/       Riverpod providers (alarms, crew, stats, subscription, session)
  domain/      Entities + rules (Alarm, SnoozePolicy, Mission, Streak,
               WakeEvent, ScheduleMath)
  data/        Repositories over three sources:
               - Drift (SQLite): local source of truth for alarms/events
               - Supabase client: social, profiles, stats sync
               - Pigeon platform channels: native alarm engine
```

- Navigation: go_router. Audio preview: just_audio. Recording: `record` (AAC/m4a ≤15 s). Health: `health` package (HealthKit + Health Connect). Billing: purchases_flutter (RevenueCat). Crashes: Sentry. Analytics: PostHog.
- **Local DB is the source of truth for anything that must ring.** Native scheduler mirrors the DB via a reconcile pass run on: app launch, alarm edit, dismissal, boot, timezone/time change, push receipt.

### Supabase backend

**Tables** (all with RLS):

| Table | Purpose / key columns |
|---|---|
| `profiles` | id=auth.uid, username (unique), display_name, avatar_color, tz, streak_current, streak_best, streak_freezes, premium_until (RevenueCat mirror), settings jsonb (let_crew_wake_me, bedtime, social_escalation_opt_in, gentle_mode) |
| `friendships` | user_lo, user_hi (canonical order), status: pending/accepted, requested_by |
| `invites` | code, inviter_id, expires_at, max_uses, uses |
| `groups` / `group_members` | name, owner_id / group_id, user_id |
| `alarm_gifts` | from_user, to_user OR group_id, h/m/ampm, days[], label, note, sound, mission, difficulty, voice_clip_id?, status: pending/accepted/declined/expired |
| `voice_clips` | owner_id, storage_path, duration_s, moderation_status, expires_at (30 days) |
| `wake_events` | user_id, scheduled_at, first_ring_at, dismissed_at, method, snooze_count, mission_failures, on_time, tz — powers streaks/stats/status/leaderboard |
| `status_events` | user_id, status: asleep/waking/awake, at, next_alarm_at? |
| `nudges` | from_user, to_user, at (rate-limited) |
| `device_tokens` | user_id, platform, fcm_token |
| `reports` / `blocks` | UGC moderation |

**RLS policies:** own rows writable; friend-visible reads only for accepted friendships; voice clips readable by owner + recipient only; free-tier limits (1 group) enforced by policy/trigger, not just UI.

**Storage:** private `voice-clips` bucket; clips auto-expire after 30 days (cron).

**Edge Functions:** `send-push` (FCM HTTP v1 → both platforms; FCM relays to APNs), `fanout-alarm-gift`, `accept-invite`, `compute-streaks` (daily cron; applies freezes), `social-escalation` (per-minute cron: `first_ring_at` set, no `dismissed_at`, > 10 min, user opted in → push crew), `delete-account` (full purge: rows + storage + auth), `revenuecat-webhook` (entitlement sync).

**Auth:** Supabase Auth, Apple + Google providers.

### Key data flows

1. **Local alarm:** UI → Drift → reconcile → native scheduler. Zero network dependency.
2. **Voice alarm:** record → Storage upload → `alarm_gifts` insert → Edge push → recipient background-downloads clip → local pending alarm (or auto-accept) → scheduler. Clip missing at ring → default sound, attribution kept.
3. **Live status:** clients publish transitions (bedtime→asleep, ring→waking, dismiss→awake); friends subscribe via Realtime; countdowns computed client-side from `next_alarm_at`.
4. **Nudge:** insert → Edge Function → high-priority FCM push with sound. Rate-limited server-side.
5. **Premium:** RevenueCat purchase → webhook → `profiles.premium_until` → server-side gates + client unlock. RevenueCat SDK is entitlement source of truth client-side.

### Consent & safety model for social alarms

- Alarms/voice alarms from friends arrive as **requests** (accept/decline) unless recipient enabled **"Let crew wake me"** (auto-accept from accepted crew only).
- Group alarms follow the same per-member rule.
- Report + block from day one; blocked users can't send anything. Voice clips have a moderation status and can be taken down.

### Offline behavior

Alarms, missions, streak display, and cached stats fully offline. Social actions fail gracefully or queue (gift sends queue; nudges require network and show clear errors). Realtime reconnects with backoff; status falls back to last-known + timestamps.

---

## 4. The Alarm Reliability Engine (native modules)

Thin Pigeon API: `scheduleAlarm`, `cancelAlarm`, `reconcile(alarms[])`, `getRingingState`, `getPermissionStatus`, `runAlarmTest`.

### iOS (deployment target iOS 16)

- **iOS 26+ — AlarmKit** (WWDC 2025, session 230): system-grade alarms — full volume, **breaks the silent switch and Focus**, survives app termination, with a full-screen Lock Screen alert, Dynamic Island and StandBy presentation. `AlarmManager.shared.requestAuthorization()` / `schedule(id:configuration:)` / `cancel(id:)`; `Alarm.Schedule.fixed`/`.Relative` with weekly recurrence. The alert's **secondary button fires an App Intent that opens Rise → mission UI**. Requires `NSAlarmKitUsageDescription`; countdown presentation requires a Live Activity in a widget extension. Primary path for the large majority of devices.
- **AlarmKit constraints that shape the design** (all verified against Apple docs/field reports):
  1. **It does not wake the app** at alarm time — no custom pre-ring logic.
  2. **Bundled/local sounds only.** Friend voice clips must be downloaded to `/Library/Sounds` **before bedtime**, never streamed at ring time. Hence the pre-bedtime clip-download pass; missing clip → default sound + attribution kept (§3).
  3. **No callback when the user swipes the alarm away.** Rise cannot know a bare dismissal happened → **every AlarmKit alarm is paired with a Wake-Up Check**, which doubles as the back-to-sleep catcher. This is why Wake-Up Check is free and non-optional infrastructure, not a premium extra.
- **iOS 16–18 — engineered notification stack:** per alarm, a burst of local notifications 30 s apart (each with a 30 s custom sound — longer files are silently replaced by the default — at Time-Sensitive interruption level, which breaks Focus but **not** the mute switch). iOS caps 64 pending notifications per app: nearest alarm gets a full burst (~16), others get placeholders; budget recomputed at every reconcile.
- **Critical Alerts: not planned for.** The entitlement is approval-gated and consumer alarm apps are routinely refused ("this API is not designed for the use you've identified"). We may apply, but no feature, claim, or launch date depends on it.
- **No overnight keep-alive.** Sleep Cycle's stay-alive model is the documented cause of battery-drain churn (Alarmy's #1 complaint) and dies on force-quit anyway. AlarmKit replaces the need on 26+; pre-26 accepts the honest degradation below.
- **Honest pre-26 degradation:** force-quit + silent switch → notifications that vibrate only. Stated plainly in Setup Guardian on affected devices rather than papered over.
- App awake at ring time → full audio-session takeover (looping, ramp control).

### Android (minSdk 26, targetSdk latest)

- `AlarmManager.setAlarmClock()` — exact, **exits Doze shortly before firing**, never time-shifted by the system, shows the system alarm indicator. (Not `setExactAndAllowWhileIdle()`, which Doze throttles to once per 9 min per app.)
- Permissions: **`USE_EXACT_ALARM`** (API 33+) — install-granted, **not user-revocable**; Play restricts it to alarm/timer/calendar core-function apps, which Rise is. `SCHEDULE_EXACT_ALARM` fallback for API 31–32 (revocable → `canScheduleExactAlarms()` check + re-request flow).
- Ring pipeline: broadcast receiver → **foreground service (`systemExempted` type — explicitly covers exact-alarm holders continuing an alarm; background start from the alarm PendingIntent is an allowed exemption)** → full-screen intent notification (Play auto-grants `USE_FULL_SCREEN_INTENT` to alarm apps since Jan 2025; verify `canUseFullScreenIntent()`, deep-link to settings if revoked) → ringing activity with `setShowWhenLocked` + `setTurnScreenOn` → audio on `AudioAttributes.USAGE_ALARM` (dedicated alarm stream, immune to media mute) + VibratorManager pattern + wake lock. `setBypassDnd(true)` only after the user grants notification-policy access.
- Receivers: `BOOT_COMPLETED`, `MY_PACKAGE_REPLACED`, `TIME_SET`, `TIMEZONE_CHANGED` → reconcile. Missed-alarm recovery: due within last 30 min and undismissed → ring now.
- OEM killer defense — **the #1 real-world failure source, not a footnote**: Samsung sleeps unused apps after ~3 days (and resets the setting on OS updates); Xiaomi needs manual Autostart with no reliable deep-link; Huawei's PowerGenie is worst. Guardian detects the OEM, requests `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` (permitted by Play policy when core function is affected), walks per-OEM steps, and **re-checks periodically** because these settings silently revert.

### Escalation ladder (per alarm, both platforms)

1. Gentle start: volume ramps from low over 60 s (abrupt waking spikes blood pressure)
2. Full volume + vibration + max screen brightness
3. Snooze budget: shrinking snoozes (9→5→3 min default), then snooze button disappears; mission required
4. Wake-up check: "Still up?" at +5 min (configurable 1–30); unanswered within 100 s → full re-ring
5. Social escalation (opt-in): unacknowledged > 10 min → crew nudge push

### Edge-case matrix

| Case | Behavior |
|---|---|
| Reboot / app update | Reconcile on boot/update; missed-alarm recovery (≤30 min late, undismissed → ring) |
| App force-killed | Android: AlarmManager still fires. iOS 26+: AlarmKit fires. iOS fallback: notification stack fires |
| Silent / vibrate / DND / Focus | Android alarm stream + AlarmKit bypass. iOS fallback: Time-Sensitive + Guardian warnings |
| Volume keys during ring | Ringing screen swallows volume-down; alarm-stream volume re-asserted every 1 s |
| Overlapping alarms | Priority queue: earliest rings; next queues after dismissal |
| Alarm during call | Reduced volume + vibrate; full ring after call ends |
| DST spring-forward (nonexistent time) | Fires at first valid instant after; fall-back duplicate fires once |
| Timezone travel | Alarms follow local wall clock; recompute on TIMEZONE_CHANGED |
| Time set backwards/forwards manually | TIME_SET → reconcile; alarms recomputed from wall clock |
| Voice clip missing/undownloaded | Default sound + attribution chip |
| Storage full / sound file corrupt | Bundled default sound always ships in binary; fallback chain |
| Battery will die before wake time | Mid-night battery alarm: projected charge < needed → wake user to plug in. Bedtime reminder also warns at wind-down |
| Battery dead / phone off | Cannot ring (honest in marketing). Cloud `wake_event` still records the miss; crew still gets the escalation push |
| iOS user swipes AlarmKit alarm away | No callback exists → Wake-Up Check catches it; unanswered → re-ring |
| Voice clip not downloaded before bedtime | Pre-bedtime download pass; on failure → default sound + attribution chip (AlarmKit cannot stream at ring time) |
| Photo mission: registered spot unreachable (travel, dark room) | Fallback mission offered after 2 failures; repeated fallback prompts re-registration. Never traps the user |
| Goal-lock vs genuine schedule change | Lock is 4 h pre-alarm; emergency unlock always available at the cost of the streak. Gentle mode disables locking |
| Stuck in mission (safety) | After repeated failures: "Hold 10 s to end alarm" — ends alarm, breaks streak, notifies crew. Never traps the user |
| Sleep disorders / shift work | Gentle mode: no mission pressure, softer escalation, pausable streaks |
| Notification permission revoked later | Guardian banner on next launch + degraded-mode warning |
| Multiple devices, one account | Alarms are per-device by design; wake_events tagged by device; documented v1 assumption |
| Clock skew / server time | All ring decisions use device wall clock; server timestamps only for social/stats |

### Anti-cheat posture

We do not attempt local lockdown. Alarmy's prevent-power-off is OEM-dependent hackery that broke on stock Android 12+; nobody can block iOS force-quit or uninstall. **Rise's answer is cloud-recorded outcomes** (Nuj's insight): the alarm's fate is a server-side `wake_event`, so powering off, force-quitting, or reinstalling doesn't erase the consequence. Any dirty escape (kill, uninstall-reinstall, clock fiddling caught by monotonic checks) costs the streak and pings the crew. Goal-locking closes the last honest-looking cheat — moving the alarm at 2 a.m.

**The social layer is the anti-cheat.** Local enforcement can always be beaten by a determined groggy human; a friend noticing you didn't get up cannot.

---

## 5. Screens & UX

### From the prototype (pixel-faithful to Rise.dc.html)

Onboarding (3 slides + sign-in) · Home (greeting/streak pill, next-alarm hero with live countdown + Preview, Crew·live strip, alarm rows with day chips + toggles) · Create/Edit alarm (drag time dial ±7 px/step with wrap, AM/PM segmented, day chips with smart repeat label, label field, sound chips, mission radio list + difficulty segmented, friend variant with note + voice attach, edit variant with delete) · Ringing overlay (pulsing bell, giant mono clock, label, voice chip with waveform, snooze button, slide-to-wake ≥97%) · Mission overlays (Math keypad flows, Hold conic-fill random targets, Tap random targets, Memory 2×2 sequence) · Crew (Friends/Groups segments, stat cards, friend rows with nudge, group cards) · Friend detail (stats, Set alarm / Voice alarm, their alarms) · Group detail (Wake group, Nudge all, members, Manage) · New group · Manage members · Voice recorder (timer, waveform, 15 s cap, play/re-record/send) · Sleep stats (avg sleep + delta, consistency ring, 7-night bars, sleep debt, wake-vs-set, snooze mini-bars, leaderboard) · Profile (settings list) · Tab bar (Home/Crew/+FAB/Sleep/You) · Toasts.

Design tokens exactly per handoff README: mono palette, Geist/Geist Mono, radii 9/13/18/999, specified shadows, 20 px screen padding, 44 px hit targets, listed animations (bell-swing, glow, wave, pop-in, sheet-up, toast-up, dot pulse).

### New screens for the real product

1. **Setup Guardian** (post-sign-in onboarding + health checks on every launch): username claim → notification permission → alarm permissions (Android FSI/battery exemption per-OEM; iOS volume/Focus guidance) → bedtime & wake goal → **Test my alarm** (real 1-min alarm proves the pipeline) → invite crew (share sheet) → soft paywall (trial, skippable). Revoked protections → warning banner.
2. **Paywall (Rise Plus):** onboarding end, gated-feature taps, Profile. Monthly/annual + trial, price/terms/restore per store rules.
3. **Add friends:** invite-link share sheet, username search, incoming requests.
4. **Alarm-gift inbox:** pending gifts as Home card + push deep-link; sent gifts show await/accepted status.
5. **New missions in the prototype's visual language:** Typing, Shake, **Photo** (register a reference spot → re-shoot it; on-device perceptual-hash match with a "close enough" tolerance and a visible retry count), **QR/Barcode** (register a code on the coffee machine/bathroom door → scan it).
6. **Streak detail sheet:** on-time calendar, freezes, forgiveness explainer.
7. **Settings (expanded):** snooze policy editor, escalation + social-escalation opt-in, wake-up check timing, goal-lock toggle, mission reference manager (registered photo spots / QR codes), default sound + rotation, bedtime reminder, Gentle mode, notifications, manage subscription, account (username, delete account, sign out), legal.
8. **All empty/edge states:** no alarms, no crew (invite CTA), pre-first-week stats, offline banner, clip expired, blocked user.

### Flow notes

- Snooze button shows live budget ("Snooze 5 min · 1 left"), disappears when spent; slide-to-wake launches mission when set.
- Wake-up check notification has "I'm up" action; ignored → re-ring.
- Deep links: invite → accept-friend; gift push → inbox; nudge → Home.
- Accessibility: 44 px targets, full semantics, dynamic type, reduced-motion respect.
- V1 = mono light theme only; midnight theme deferred deliberately. English-only; strings externalized.

---

## 6. Streaks, stats & gamification rules

- **Streak increments** when the user dismisses an alarm within the on-time window (≤10 min after scheduled time) on a day with an active alarm. Server (`compute-streaks` cron) is authoritative; client optimistic.
- **Freezes:** 1 earned per 7 consecutive on-time days (cap 2 free / 5 Plus). A missed day consumes a freeze automatically; else streak resets. Streaks pause in Gentle mode or declared "off days" (weekends without alarms don't break streaks — streak counts *alarm days* only).
- **Consistency score:** rolling 14-day std-dev of wake times mapped to 0–100 (the prototype's ring).
- **Leaderboard:** crew-scoped, streak-ranked; "you" row highlighted.
- **Sleep estimate:** bedtime-reminder ack (or phone-lock heuristic where available) → first dismissal; Health samples override when present. Labeled as estimates in UI.
- **Wake rate** (internal north-star metric): % of scheduled rings dismissed within 5 min.

---

## 7. Monetization

- Product: `rise_plus` subscription — **$4.99/mo or $29.99/yr, 7-day free trial**. RevenueCat manages offerings/receipts; entitlement `plus`. No ads, ever.
- **Pricing rationale** (market anchors: Alarmy $59.99/yr, Sleep Cycle $39.99/yr, new wave $19.99–39.99/yr, Galarm $9.99/yr): price *under* the incumbents. Rise's growth depends on friends joining friends — a high wall kills the network effect that is the whole product. Annual at $29.99 undercuts Alarmy by half while beating Galarm's revenue per user. Prices are a launch hypothesis; RevenueCat makes them A/B testable.
- Paywall triggers: onboarding soft-sell (skippable), 4th alarm, 2nd group, hard difficulty select, mission chaining, stats history swipe, custom sound upload, dawn simulation toggle.
- **Never paywalled, on principle:** the alarm itself, any reliability feature (Setup Guardian, Wake-Up Check, escalation, battery alarm), and the entire social core. The category's #1 review complaint is paywalling the alarm (Wayk) or the safety features (Alarmy's Wake-Up Check). **No ad-to-snooze** — Alarmy's version generated a press backlash.
- Store compliance: price + renewal terms on paywall, Restore Purchases button, subscription management link.

---

## 8. Security, privacy & compliance

- RLS-first backend; no service keys in the app; Edge Functions validate auth JWT.
- Voice clips: private bucket, sender+recipient read only, 30-day expiry, report/block + moderation status (Apple UGC rules: report + block + takedown path required).
- Privacy policy + terms on a static site; in-app links. Data safety forms (Play) + privacy nutrition labels (Apple) enumerated from actual SDK list.
- In-app account deletion (Apple requirement) via `delete-account` Edge Function: purges rows, storage, auth user.
- Age rating 13+; no ads; no cross-app tracking → no ATT prompt. PostHog first-party analytics with opt-out toggle.
- **Camera** (photo/QR missions): permission requested at mission setup, not at launch. **Reference photos and mission shots never leave the device** — matching is on-device perceptual hashing; only pass/fail is recorded. Stated in both privacy forms and the mission setup screen.
- GDPR basics: deletion (above), export on request (manual acceptable at launch), minimal PII (email from OAuth, username).
- Android declarations: `USE_EXACT_ALARM` (core alarm functionality), full-screen intent, foreground service type + justification video for review.
- Apple: Sign in with Apple present; background modes only as needed; Critical Alerts entitlement filed separately.

---

## 9. Quality & delivery

### Testing

- **Unit (heaviest):** ScheduleMath — repeat days, DST spring/fall, timezone shifts, wall-clock changes, snooze budgets, streak/freeze rules, reconcile idempotency, notification-budget allocation (iOS 64 cap).
- **Native:** Android instrumented tests (schedule→receiver→service→FSI; boot reschedule); iOS XCTest (AlarmKit wrapper, stack budgeter).
- **Widget + golden tests:** every screen pinned to prototype visuals.
- **E2E (Patrol):** create→ring→mission→dismiss; invite→accept→voice alarm delivered; paywall purchase (sandbox).
- **Alarm Reliability Protocol** (pre-release, physical devices incl. one Xiaomi-class OEM): locked / silent / DND / Focus / force-killed / post-reboot / Doze (adb-forced) / low battery / mid-call. **Launch gate: ≥99.5% ring delivery; crash-free ≥99.5%.**
- **Backend:** RLS policy tests, Edge Function tests, separate staging project.

### CI/CD & environments

- GitHub + Actions: analyze, test, golden checks on PR.
- Codemagic: iOS (TestFlight) + Android (Play tracks) builds, managed signing — no Mac required.
- Shorebird: OTA Dart patches post-release.
- Environments: dev (Supabase local docker) / staging / prod (separate projects), config via dart-define.
- Sentry releases + PostHog dashboards (wake rate, activation: first alarm set / first dismissal, D1/D7 retention).

### Launch sequence

1. Internal builds → 2. TestFlight + Play closed testing with the crew (**Play requirement: new personal accounts need 12+ testers × 14 days before production**) → 3. Store listings (screenshots, privacy forms, review notes explaining alarm permissions) → 4. Staged rollout 10%→50%→100% watching wake-rate + crash-free dashboards.

### Build order (implementation plan will detail)

Foundations + design system → native alarm engine + local alarms E2E on devices (riskiest first) → missions + ringing → accounts + crew → voice alarms + escalation → stats/streaks/premium → compliance hardening → beta → submission.

---

## 10. Non-goals (v1)

Phone auth / contact sync; wearables & widgets; money stakes; morning feed / reactions; friend-ping-to-record loop; nap timer; sleep-stage tracking & smart-wake; dark theme; localization; ads; web app; tablet-optimized layouts (phone-first, tablets get scaled phone UI).

---

## 11. Research appendix (evidence grounding)

Key findings applied (confidence-graded in the full research reports):

- Sleep regularity → ~30–48% lower all-cause mortality; stronger predictor than duration (UK Biobank n=60,977) → consistency is the hero metric.
- Low-frequency ~520 Hz signals wake 4–12× better than high-pitch; survive hearing loss (NFPA-mandated for sleeping areas) → default sound engine.
- Melodic alarms → less perceived sleep inertia (McFarlane 2020, N=50, self-report) → melodic defaults.
- Haptics wake ~95–100% (deaf-adult and EEG-arousal studies) → vibration in every escalation ladder.
- Bounded ~30 min snooze not clearly harmful, may modestly help (Sundelin 2023, survey n=1,732 + lab n=31) → snooze budget, no shaming. 55.6% of 3M+ sessions end in snooze (Sci Rep 2025) → snoozers are the market.
- Voice of a loved one woke 86–91% of children vs 53% for tone (Smith & Splaingard 2018) — does NOT generalize to older adults → voice alarms framed as emotional/social feature for a young base, not universal claim.
- Streak freezes / forgiveness raise retention (Duolingo A/B at scale); habits plateau ~66 days median (Lally 2010) → freeze mechanics.
- Competition > support for sustained behavior (STEP UP RCT, JAMA IM 2019) → leaderboard central.
- Money stakes: potent per-user, ~14% uptake vs 90% for rewards (NEJM 2015) → deferred, opt-in only.
- Nudge/friction effects small after publication-bias correction (PNAS 2022) → friction alone isn't the product; layered defense is.
- No RCT validates mission-dismissal reducing oversleeping → missions framed as anti-snooze friction + engagement; Rise can A/B its own evidence.
- Smart-wake windows: stage detection 60–85% accurate; controlled test showed no benefit → excluded from v1.
- Abrupt waking spikes morning blood pressure (pilot n=32) → gentle ramp default.
- Severe sleep inertia is clinical in hypersomnia/depression; shift workers ~20% of workforce → Gentle mode + compassionate copy.
- Olfactory alarms don't work (olfaction suppressed in sleep) → no scent gimmicks.

Full report: `../research/2026-07-15-wake-behavior-research.md`.

### Competitor evidence applied

Full report: `../research/2026-07-15-competitor-research.md`. Load-bearing findings:

- **Alarmy** (110M+ downloads, ~4M DAU, ~$33M revenue) owns missions, has **no social layer**. Its Wake-Up Check (100 s countdown → re-ring) is the highest-leverage wake feature in the category → Rise ships it free.
- **Photo/QR are the most-praised missions** across Alarmy, I Can't Wake Up!, Sleep as Android, Nuj → pulled into v1; every prototype mission is completable in bed.
- **Erly's goal-locking** (wake time locks 4 h out) → adopted; without it streaks and leaderboards are unfalsifiable.
- **Galarm** proves social alarms work *and* warns why they fail: its top complaint is alarms 30+ min late from server dependency → Rise's alarms never touch the network.
- **The graveyard** (Kiwake, Walk Me Up, Step Out!, Mimicker) died from OS updates breaking background hacks + abandonment → reliability engineering is the moat.
- **AlarmKit (iOS 26)** enables system-grade third-party alarms — and spawned four direct social-alarm competitors (Wake, YouUp, NOX, Alarm Friend) in the last year, none with traction yet. Its three constraints (no app wake, local sounds only, no swipe-dismiss callback) directly shape §4.
- **Critical Alerts is routinely refused** for consumer alarm apps → not planned for.
- **OEM battery killers** (Samsung ~3-day sleep, Xiaomi autostart, Huawei PowerGenie) are the #1 real-world failure source → Setup Guardian is a headline feature, not onboarding filler.
- **Pricing anchors:** Alarmy $59.99/yr, Sleep Cycle $39.99/yr, new wave $19.99–39.99/yr, Galarm $9.99/yr → Rise at $29.99/yr. Category's #1 complaint is paywalling the alarm or its safety features → both free forever.
- **Nuj's cloud-recorded outcomes** defeat power-off cheating without OEM hacks → adopted as Rise's anti-cheat model.
