# Mobile Alarm App Competitive Landscape — Research Report for Rise

**Date:** 2026-07-15
**Purpose:** Competitive and platform-reliability evidence for the Rise design spec (`../specs/2026-07-15-rise-alarm-app-design.md`).
**Method:** Multi-agent web research; 45 load-bearing claims put through 3-vote adversarial verification (42 confirmed; corrections and unresolved items listed in §5).

---

## 0. Executive summary

- **A dominant incumbent owns "missions" but has no social layer.** Alarmy: 110M+ downloads, ~4M DAU, ~$33M revenue — and mounting complaints about subscription aggression and battery drain.
- **The classic physical-action apps are all dead** (Kiwake 2021, Walk Me Up delisted, Step Out! 2019, I Can't Wake Up! dormant since July 2023). The niche consolidated into Alarmy plus small indies. **They died of two diseases: OS updates breaking background hacks, and solo-dev abandonment. Reliability engineering is the moat, not mission creativity.**
- **Apple's AlarmKit (iOS 26, WWDC 2025) changed the game.** Third-party alarms can break Silent mode and Focus with a system full-screen alert. It triggered a wave of late-2025/2026 entrants — including apps doing *exactly* Rise's concept.
- **Four apps now converge on Rise's idea:** Wake: The Social Alarm (friend voice alarms + group alarms + morning feed), YouUp (friend voice alarms), NOX (friend video alarms), Alarm Friend. **None has traction yet — the window is open but no longer empty.**
- **TikTok UGC is the proven distribution channel.** Wayk: 25M views, #15 App Store, 100K+ downloads in 30 days, no VC money. Erly rode the same playbook to 4.8★/16K ratings.
- **"100% wake" is an engineering claim before a feature claim.** No app can truthfully guarantee it today: on iOS a force-quit app on silent degrades to vibrating notifications (Alarmy admits this); on Android, OEM battery killers are the top real-world failure cause.
- **Naming collision:** at least four unrelated "Rise" alarm apps exist on the stores (e.g. https://apps.apple.com/us/app/rise-motivational-alarm/id6751260620, https://play.google.com/store/apps/details?id=rise.balitsky). None is social, but expect App Store search collision and trademark diligence.

---

## 1. Per-competitor summaries

### 1.1 Alarmy (Delight Room) — the category king

- **Scale:** 110M+ cumulative downloads, ~4M DAU, #1 alarm app in ~97 countries; ~₩46B (~$33M) annual revenue, ~50 staff; 2023 Google Play App of the Year. iOS 4.8★/~240K ratings; Play ~4.6★/~2M ratings. (https://alar.my/en · https://delightroom.com/ · https://apps.apple.com/us/app/alarmy-alarm-clock-sleep/id1163786766 · https://play.google.com/store/apps/details?id=droom.sleepIfUCan)
- **Wake enforcement:** 8 core missions — Math, Photo (re-shoot a registered spot), Shake (up to 999×), Barcode/QR, Memory, Typing, Walking/Steps, Squat (https://alar.my/en/blog/alarmy-wake-up-mission). Premium "Multiple Missions" chains 2–5 per alarm. **Wake Up Check** (premium): silent check-in after dismissal; miss the 100-second countdown → alarm re-fires with missions (https://alarmy-android.zendesk.com/hc/en-us/articles/900000759543). **Extra Loud Effect**: unresponsive 40 s → super-loud blast; **Label Reminder** reads the alarm label every minute. Anti-cheat: Android-only prevent-power-off / prevent-uninstall during ringing — **broke on stock Android 12+**, now works only on certain OEMs (Samsung, Xiaomi, Motorola, Vivo, Realme, Oppo) (https://alarmy-android.zendesk.com/hc/en-us/articles/4426309959321).
- **Social:** none. Content instead: "Today's Panel" (weather/news/horoscope with ads), sleep tracking with snore recording, sleep sounds.
- **Monetization:** free with ads (including **watch-an-ad-to-snooze** after the cap — https://futurism.com/alarm-app-advertisement-snooze); Premium $4.99–8.99/mo, **$59.99–69.99/yr**, 7-day trial. Gates: Typing/Walking/Squat/Multiple missions, Wake Up Check, Extra Loud, custom sounds, ad removal. Heavy paywall A/B testing (https://adapty.io/paywall-library/alarmy/).
- **Loved:** "actually gets me out of bed," loudness, mission variety, photo/QR missions.
- **Complaints:** **battery drain is the #1 churn theme** in mid-2026 review analysis (https://marlvel.ai/intel-report/lifestyle/alarmy-loud-alarm-clock); alarms not ringing from OEM battery killers/missing permissions (they maintain a per-OEM troubleshooting library: https://alarmy-android.zendesk.com/hc/en-us/articles/360004239093); iOS force-quit + silent → notifications that **only vibrate** (https://alarmy-ios.zendesk.com/hc/en-us/articles/360004372234); "used to be $2 one-time, now nagging subscription"; ad-to-snooze backlash.

### 1.2 Sleep Cycle — the sleep-science incumbent (not an enforcement app)

Smart alarm rings at lightest sleep inside a **10–30 min window**; patented microphone sound-analysis or accelerometer tracking (https://sleepcycle.com/the-app/smart-alarm). iOS 4.7★/~27K ratings, 40M+ downloads claimed. **Public company in decline: 918K paying subscribers end-2024 → 715K in Q1 2026** (https://sleepcycle.com/newsroom/press-release/sleep-cycle-interim-report-january-march-2026). Premium ~**$39.99/yr** (up from $29.99). No social, no anti-snooze. Complaints: accuracy (~50–70% vs polysomnography), billing anger, fragile delivery (app must stay alive overnight; fires a **mid-night battery alarm** to make you charge — https://support.sleepcycle.com/hc/en-us/articles/14775944184476).

### 1.3 Alarm Clock Xtreme (Avast/AVG) — Android mass-market utility

**Android-only** (the iOS listing of that name is an unaffiliated copycat). 50M+ installs, ~4.7★, actively updated (Apr 2026). Tasks: math (5 tiers), rewrite/typing, steps, QR/barcode (premium); snooze caps, **decreasing snooze durations**, gentle 30-min ramp (https://support.avg.com/SupportArticleView?l=en&urlname=AVG-Alarm-Clock-Xtreme-FAQ). Monetization: ads + **one-time per-item purchases**, no subscription. No anti-cheat — its own docs concede alarms die if the OS force-stops the app. Complaints: intrusive ads, alarms stopping early, lasting resentment from the 2019 forced Pro repurchase.

### 1.4 I Can't Wake Up! (Kog Creations) — the abandoned pioneer

8 tasks (Math, Memory, Order, Repeat, Barcode, Rewrite, Shake, Match); **WakeUp Guard** blocks exiting/powering off/force-stopping during an alarm (dev admits it broke with Android 10 on some devices — https://i-cant-wake-up.nolt.io/20); **Awake Test** re-fires the alarm minutes after dismissal. Free + ads; one-time ad removal. Play ~4.1★/~86K ratings. **Last update July 2023 — dormant**, untested against Android 14/15/16.

### 1.5 Galarm (Acintyo) — the social/group alarm incumbent

Group alarms ring **simultaneously for all participants**, each with its own chat; **buddy alarms** ("you're notified if your buddy misses the alarm"); **instant alarms** ring immediately on a friend's phone (https://www.galarmapp.com/). 4.7★/~4.2K iOS ratings; 6M+ downloads claimed. Free tier = **1 group alarm**; Premium **$0.99/mo, $9.99/yr, $24.99 lifetime**. No missions, no anti-snooze — enforcement is purely social visibility. **Complaints are the cautionary tale: delayed alarms (30+ min late), recurring alarms silently failing — social alarms add a server/sync dependency to a must-never-fail local system.**

### 1.6 The graveyard — dead physical-action apps

- **Kiwake** (iOS): photo of a far object + brain game + read your goals. $1.99/mo. **Last update Apr 2021**; "iOS 14 rendered it completely useless" — it was really a notification prompting you to open the app.
- **Walk Me Up!** (Android/iOS): walk N steps, shake anti-cheat, "Evil Mode." 500K+ installs at peak; **delisted from Google Play**.
- **Step Out!** (iOS): steps or reference-photo, $1.99 one-time, 4.1★/~6.1K. **Last update Dec 2019**; defeated by vibrate mode or the power button.
- **Mimicker Alarm** (Microsoft Garage): selfie-emotion dismissal; repo archived July 2024.

### 1.7 Money-stake / commitment apps

- **Paywake** (alive, May 2026): stake money on waking; photo proof of a household object; winners split losers' forfeits, streak bonuses to +25%. Company-stated specifics ($5–99 stakes, 3-min window, 15% cut) uncorroborated — treat as claimed (https://paywake.com/). "Gambling-like" criticism.
- **Forfeit** (alive): stake on any goal incl. waking; photo/GPS proof; claims 94% success across 75K+ goals (https://www.forfeit.app/).
- **Nuj Alarm Clock** (v1.0.24 Dec 2025): no snooze; scan a pre-registered barcode within ~5 min or pay a self-set **$5–50 penalty to charity**; **alarms stored in the cloud so powering off doesn't escape the penalty**; 4.7★/81 ratings (https://nuj.app/).
- **Beeminder** (pledge ladder $5→$10→$30→$90) and **stickK** (~451K contracts, $40M+ staked) prove commitment contracts at scale outside alarms.

### 1.8 Social alarm apps — history and the new AlarmKit wave

- **Wakie** (2014): strangers call to wake you; pivoted to stranger voice-chat; Play 5M+ bracket; Plus from $9.99/mo.
- **Snoozle** (2018, £135K crowdfunded, 12-second friend voice-message alarms — *Rise's exact voice feature, 8 years early*): **abandoned Jan 2021**.
- **Wake: The Social Alarm** (iOS-only, **requires iOS 26**, free with ads): record a voice message for a friend → becomes their alarm; group alarms; post-wake feed with reactions; built on AlarmKit (https://apps.apple.com/us/app/wake-the-social-alarm/id6754577206). **The closest existing app to Rise.** No traction data — too new.
- **YouUp** (UC Berkeley students, iOS, free): when your alarm approaches, **a random friend is pinged to record audio** that plays as your alarm; friend "circles" (https://www.youup.io/).
- **NOX** (Lapsus, France; global launch Jan 2026): wake to videos from friends/creators; "Flux" feed (https://apps.apple.com/us/app/nox-the-social-alarm-clock/id1557526565).
- **Alarm Friend** (Dec 2025, iOS 26/AlarmKit): alarm requests with voice messages to approved friends; QR friend-adding; $1.99/wk or $9.99/yr.

### 1.9 New gamified entrants (TikTok wave, 2025–2026)

- **Wayk** (Dialed Labs): missions before dismissal (pushups, sky photo, make your bed, object hunt) + streaks. **First 30 days: 25M TikTok views, #15 App Store, 100K+ downloads, zero VC** (https://read.first1000.co/p/how-an-alarm-app-got-25-million-views). Now 4.8★/~18K. **Hard paywall: subscription required to set any alarm** — $6.99/wk, $9.99/mo, $19.99–39.99/yr.
- **Erly: Wake Up Early** (Glacier Labs): streaks, win/loss record, photo verification, and **goal-locking — within 4 hours of wake time your goal locks in**; 4.8★/~16K; $6.99–39.99; TikTok-driven.
- **Awake** (Leo Mehlig, of Structured; Sept 2025): first prominent AlarmKit-native mission alarm + Morning Briefing; **$6.49/mo or $19.99/yr** (https://techcrunch.com/2025/09/15/awakes-new-app-requires-heavy-sleepers-to-complete-tasks-in-order-to-turn-off-the-alarm/).
- **Active Android indies:** Sleep as Android (CAPTCHA QR/NFC/math dismissal), Puzzle Alarm Clock (1M+ installs, "Wake-up Poke" motion re-check), AMdroid, Early Bird, QRAlarm (open-source, blocks leaving the alarm screen), Shake-it Alarm.

---

## 2. Feature matrix

| App | Missions | Wake-check / re-alarm | Anti-cheat | Social | Sleep stats | Price anchor (US) | Platforms | Status / scale |
|---|---|---|---|---|---|---|---|---|
| **Alarmy** | 8 types + chaining | Yes (100 s, premium) | Power-off/uninstall block (Android, OEM-dependent) | None | Yes + snore | $59.99/yr | iOS+Android | 110M+ dl, dominant |
| **Sleep Cycle** | None (smart wake) | No | No | None | Best-in-class | $39.99/yr | iOS+Android | 715K subs, declining |
| **Alarm Clock Xtreme** | Math, typing, steps, QR | No | No | None | No | One-time IAPs | Android only | 50M+ installs |
| **I Can't Wake Up!** | 8 tasks | Awake Test | WakeUp Guard (aging) | None | No | ~$2.99 one-time | Android | Dormant since 2023 |
| **Galarm** | None | No | No | Group alarms, buddy alarms, chat | No | $9.99/yr | iOS+Android | 6M+ dl claimed |
| **Kiwake / Walk Me Up / Step Out!** | Photo/steps/games | No | Shake detection | None | No | $1.99–14.99 | iOS/Android | All abandoned |
| **Paywake / Forfeit / Nuj** | Photo or barcode proof | Deadline window | Cloud-stored alarms; money loss | Pooled stakes (Paywake) | No | Stakes $5–99 | iOS+Android | Small, alive |
| **Wake: The Social Alarm** | None | No | AlarmKit system alarm | Voice alarms, groups, feed | No | Free + ads | iOS 26 only | Brand new |
| **YouUp / NOX / Alarm Friend** | None | No | — | Friend voice/video alarms | No | Free / $9.99/yr | iOS | Brand new |
| **Wayk** | Physical/photo missions | No | Paywall-to-set-alarm | Streaks only | No | $9.99/mo | iOS (+Android) | 100K+ dl in 30 days |
| **Erly** | Photo verification | Goal locks 4 h out | Locked deadlines | Streaks, win/loss | No | $6.99–39.99 | iOS | 16K ratings, hot |
| **Awake** | 5+ missions | No | AlarmKit | None | No | $19.99/yr | iOS 26 | Indie, press-backed |

**Rise's whitespace:** no app combines missions + wake-check + friend voice alarms + live status + leaderboards. Alarmy has enforcement without social; Galarm/Wake/NOX/YouUp have social without enforcement; Wayk/Erly have streaks without friends. The combination is genuinely unoccupied — but four AlarmKit-era startups are converging on it.

---

## 3. Feature ideas worth stealing, ranked by impact

1. **Wake-Up Check re-alarm** (Alarmy's 100-second check-in; ICWU's Awake Test; Puzzle Alarm's "Wake-up Poke"). Highest-leverage feature for a "100% wake" promise — **dismissing the alarm isn't the failure mode, falling back asleep is.** Make it free (Alarmy paywalls it) and wire it into Crew status: "Tofiq went back to sleep" is a killer social trigger.
2. **A get-out-of-bed mission: photo-of-registered-spot or QR/barcode scan.** The most-praised mission across Alarmy, ICWU, Sleep as Android, Nuj. **Rise's current set (math, hold, tap, memory) is all completable in bed — this is the biggest mission gap.**
3. **Reliability onboarding as a product feature.** Alarmy and Sleep as Android maintain per-OEM help libraries; Sleep as Android routes users to dontkillmyapp.com. Productize it: an in-app "Alarm Reliability Score" with deep links and a nightly pre-flight check. Nobody has made this delightful.
4. **Erly's goal-locking:** wake time locks N hours before the alarm — prevents the 2 a.m. "move the alarm" cheat and makes streaks/leaderboards trustworthy. Cheap to build, essential for social stakes.
5. **Voice alarms with a delivery loop, not just a recording** (Snoozle 2018 → Wake/YouUp/NOX). YouUp's twist — *pinging a friend to record fresh audio for tomorrow's alarm* — creates a daily two-sided engagement loop.
6. **Escalation ladder** (Alarmy's Extra Loud after 40 s + Label Reminder): ramp → blast → vibration + flash → **notify Crew**. The last rung is Rise-only: human backup as final fallback (Galarm's buddy-alarm notification is the best idea in Galarm).
7. **Opt-in stakes mode** (Paywake/Nuj/Forfeit): charity penalty or Crew-pot stakes. Proven willingness to pay; regulatory care needed (gambling-adjacent).
8. **Multiple-mission chaining** (Alarmy premium): 2–5 missions per alarm as "Hard Mode" — natural upsell + leaderboard difficulty multiplier.
9. **Sleep Cycle's mid-night battery alarm:** if the phone will die before wake time, wake the user to plug in. Tiny feature, directly serves the 100% promise.
10. **Snooze economics** (ACX): decreasing snooze intervals + hard caps. Skip Alarmy's ad-to-snooze (documented backlash).
11. **The Wayk distribution playbook:** founder-led TikTok UGC of ridiculous wake missions (25M views/30 days). Rise's Crew reactions and voice alarms are inherently more filmable than solo missions.
12. **Pricing posture:** anchors are $59.99/yr (Alarmy), $39.99/yr (Sleep Cycle), $19.99–39.99/yr (new wave), $9.99/yr (Galarm). **The #1 review complaint across the category is paywalling the alarm itself (Wayk) or the safety features (Alarmy).** Keep enforcement + reliability free; charge for social extras, stats depth, hard mode.

---

## 4. Platform reliability — how to actually ring 100% of the time

### 4.1 iOS

**Pre-iOS 26 constraints (still apply to the fallback path):**
- Notification sounds capped at **30 seconds**; longer files silently fall back to default (https://developer.apple.com/documentation/usernotifications/unnotificationsound). Max **64 pending local notifications** per app (Apple engineer confirmation, Jan 2026 — https://developer.apple.com/forums/thread/811171). Hence the classic hack: chain notifications seconds apart to simulate continuous ringing.
- Interruption levels: `.timeSensitive` breaks Focus but **not** the mute switch; only `.critical` bypasses mute (https://developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel). **The Critical Alerts entitlement is approval-gated and consumer alarm apps are routinely refused** ("this API is not designed for the use you've identified" — https://developer.apple.com/forums/thread/690030). **Don't plan around it.**
- A terminated app cannot play custom audio. Pre-26 tactics: keep the app alive overnight (Sleep Cycle's model) or a background `AVAudioSession`. Alarmy's documented worst case: force-quit + Silent/DND → notifications that **only vibrate**.
- OS hazards: Apple confirmed native alarm failures in April 2024 (cause never officially stated; Attention Aware was the prevailing suspicion); Face ID attention detection lowers alarm volume; Bluetooth routes alarms to off-ear devices.

**iOS 26 AlarmKit — build on this** (https://developer.apple.com/documentation/AlarmKit · WWDC25 session 230):
- System-level alarms that **break through Silent mode and Focus**, with full-screen Lock Screen alert (stop + secondary button), Dynamic Island, StandBy, paired-Watch presentation.
- API: `AlarmManager.shared.requestAuthorization()` / `schedule(id:configuration:)` / `cancel(id:)`; `Alarm.Schedule.fixed(Date)` or `.Relative` with weekly recurrence; `AlarmPresentation.Alert(title:stopButton:secondaryButton:)`; **secondary button can fire an App Intent that opens your app — that's the hook for dismiss missions** (Awake ships this way). Requires `NSAlarmKitUsageDescription`; countdown presentation requires a Live Activity in a widget extension.
- **Hard limitations to design around:** AlarmKit **does not wake your app** at alarm time; **only bundled/local sounds** (friend voice recordings must be downloaded to `/Library/Sounds` before bedtime, not streamed at ring time); **no callback when the user swipes the alarm away** (https://mjtsai.com/blog/2025/06/20/ios-26-alarmkit/) — **so pair every AlarmKit alarm with a Wake-Up Check to catch silent dismissals.**
- Strategy: AlarmKit primary on iOS 26+; keep-alive + notification-chain fallback for iOS <26.

### 4.2 Android

- **Scheduling:** `AlarmManager.setAlarmClock()` — "the system never adjusts their delivery time" and **exits Doze shortly before they fire** (https://developer.android.com/develop/background-work/services/alarms). Avoid `setExactAndAllowWhileIdle()` as primary (throttled to one per 9 min in Doze).
- **Permissions:** declare **`USE_EXACT_ALARM`** (API 33+) — granted at install, **not user-revocable**; Play restricts it to apps whose core function is alarm/timer/calendar (Rise qualifies) (https://developer.android.com/about/versions/14/changes/schedule-exact-alarms · https://support.google.com/googleplay/android-developer/answer/13392821). Fall back to `SCHEDULE_EXACT_ALARM` (API 31–32; revocable — check `canScheduleExactAlarms()`).
- **Alarm UI:** `USE_FULL_SCREEN_INTENT` + `setFullScreenIntent()`. Since **Jan 22, 2025**, Play auto-grants FSI only to alarm/calling apps; verify `canUseFullScreenIntent()` and deep-link to `ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT` if revoked.
- **Audio:** ring from a **foreground service** (the `systemExempted` type explicitly covers exact-alarm holders continuing alarms — https://developer.android.com/develop/background-work/services/fgs/service-types). Play with `AudioAttributes.USAGE_ALARM` → alarm volume stream, immune to media mute. `NotificationChannel.setBypassDnd(true)` works only after notification-policy access is granted.
- **OEM battery killers — the #1 real-world failure source** (https://dontkillmyapp.com): Samsung sleeps unused apps after **~3 days** ("alarms will not work anymore" — https://dontkillmyapp.com/samsung), settings revert after OS updates; Xiaomi requires manual **Autostart** with no reliable deep-link; Huawei's PowerGenie is the worst. Mitigations: `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` (allowed by Play policy when core function is affected), per-OEM setup instructions, periodic re-checks.
- **Anti-cheat reality:** power-off blocking is OEM-dependent hackery that broke on stock Android 12+. **Nuj's cleaner answer: cloud-recorded outcomes — powering off doesn't erase the missed-wake consequence.** For Rise, social consequences survive any local cheat.

### 4.3 Honest framing of "100%"

No third-party app can literally guarantee ringing (dead battery, force-quit + pre-26 iOS silent, Huawei killers). The achievable claim: **AlarmKit + `setAlarmClock()`/FSI/foreground-service stack + reliability-score onboarding + Wake-Up Check + Crew-notification human fallback ≈ the industry ceiling** — and the human-backup layer is the one reliability mechanism *only* a social alarm app can offer. **That's Rise's story: when the OS fails, your Crew doesn't.**

---

## 5. Verification notes

42 of 45 load-bearing claims confirmed by 2–3 independent votes. **Corrections applied:** Sleep Cycle grew through 2024 (918K) before declining to 715K (Q1 2026); Walk Me Up's exact last-update date is unsupported (delisting confirmed); Wakie's Play installs are the 5M+ bracket ("10M" is a company claim); Paywake's 15%-cut / 3-min-window / $5–99 range are company-stated only; **Apple never officially blamed Attention Aware for the April 2024 alarm bug**; whether Apple's own Reminders (iOS 26.2) literally uses AlarmKit is disputed.

**Unresolved:** Alarmy's true Play install count (trackers estimate 36–48M Android; 110M is the cross-platform company figure); whether Alarmy has shipped AlarmKit as of mid-2026 (no primary source either way); Alarmy's 2026 mission paywall matrix (help center vs review-tracker conflict — they A/B test heavily).
