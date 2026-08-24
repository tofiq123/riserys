# Rise — Status (iOS: sound fixed + AlarmKit, 2026-08-24)

**Verified:** 1247 tests passing (was 1240) · `flutter analyze` clean.
Android is untouched by this round — deliberately, and checked rather than
assumed. iOS is **not** compiled or device-verified; see "needs a human" below.

Two rounds today, both iOS-only: the alarm was made *audible* (it never had been),
and then made a *real alarm* on iOS 26+ via AlarmKit.

## Shipped 2026-08-24 — the iOS alarm made a sound for the first time

Reported from a real iPhone: the alarm never fired, and even with the app open
there was no sound. Three separate defects, all on the iOS side only:

1. **No tone was ever in the app bundle.** `Copy Bundle Resources` held four
   files — the storyboards, the asset catalog, a plist. `ios/Runner/Sounds/`
   was loose on disk and unknown to Xcode, so every `UNNotificationSound(named:)`
   named a file that did not exist. iOS delivers such a notification **silently**;
   it does not fall back to the default chime, though a comment in the source and
   step 2 of the compile checklist both claimed it did. That wrong belief is why
   this shipped.
2. **56 of the 57 tones had no iOS file at all.** The library is `.ogg`, which
   iOS cannot decode for a notification sound. The whole catalog is now mirrored
   as IMA4 `.caf` (5.1 MB, all under Apple's 30 s ceiling) and is in the target.
3. **The ring screen played nothing.** `just_audio` was wired only to the sound
   picker and voice clips. Android's `AlarmService` owns the noise there; iOS had
   no equivalent, so an open app was silent by construction. `lib/data/ring_audio.dart`
   is that player, on an AVAudioSession `playback` category — the one route a
   non-system app has to be heard **through the hardware mute switch**.

A regression test now fails if a tone is ever added without its `.caf`/`.m4a`
twins, and `sound(for:)` resolves against the bundle and falls back explicitly
rather than trusting the OS.

**Also fixed in passing:** the ring screen read `AsyncValue.value` on
`alarmsProvider` — the rethrow-on-error pattern CLAUDE.md warns about, on the one
screen where an exception means an alarm cannot be dismissed. Now `valueOrNull`.

## Shipped 2026-08-24 — AlarmKit, the real iOS alarm (iOS 26+)

The sound fixes above make the notification path work as well as a notification
path *can*. They do not make it an alarm: a notification obeys the mute switch,
stops after ~30 s, and cannot draw a full-screen ring. AlarmKit does all three,
and it is what iOS 26 added for exactly this.

Plan 2 specified it (`docs/superpowers/plans/2026-07-16-ios-alarm-engine.md`,
Task 8) and it was deferred. It is now built, and the seam it needed was already
in place — `NativeAlarm` has carried `hour`/`minute`/`weekdays` from the start
for no other purpose, and `reconcile(alarms:)` existed as a documented no-op
waiting for this.

- **`ios/Runner/AlarmKitEngine.swift`** — schedules real system alarms that
  **break silent mode and Focus/DND**, are drawn full-screen by the system, and
  survive force-quit and reboot.
- **Recurrence belongs to the OS here.** iOS has no boot-receiver, so nothing
  re-arms a fired alarm; a repeating alarm is scheduled as
  `.relative(.weekly([…]))` and the system owns the repeat. This is the one
  documented exception to "Dart owns all scheduling," and Android is unaffected.
- **`capabilities()` now reports `supportsSystemAlarms: true` on iOS 26+**, so
  Dart routes itself to `reconcile()` with no Dart-side change at all. iOS 16–25
  keeps the notification burst.
- **Upgrade safety:** the first AlarmKit reconcile clears any leftover pending
  burst notifications, or an upgrading user would get every wake-up twice.
- **Authorization is separate.** AlarmKit has its own, and on 26+ it — not the
  notification switch — is what decides whether an alarm fires, so
  `getPermissions()` reports both and the Guardian can no longer show a green
  tick while alarms are blocked.

No entitlement is needed — only the `NSAlarmKitUsageDescription` string that was
already in `Info.plist`. Do **not** add `com.apple.developer.alarmkit`; it does
not exist and breaks signing.

### Needs a human — AlarmKit

- **The build machine needs Xcode 26 / the iOS 26 SDK.** `import AlarmKit` will
  not compile on anything older. Deployment target stays 16.0 — every AlarmKit
  symbol is behind `@available(iOS 26.0, *)` — so older iPhones still build and
  run the notification path. There is no `codemagic.yaml` in the repo, so
  whatever builds this has to be pointed at Xcode 26 by hand.
- **Three points marked `⚠️ VERIFY AT BUILD`** in `AlarmKitEngine.swift`, taken
  from the research doc's own confidence markers: the `Alarm` "alerting" state
  case name (matched on its description so it compiles either way), the
  non-deprecated `AlarmPresentation.Alert` initializer, and whether `.named`
  reliably plays a `.caf` on device. The compiler and the device are the
  authority on all three, not the code as written.
- Still never compiled — written on Windows, like the rest of the iOS engine.

### Needs a human — iOS

- **The alarm still shows nothing at all on the lock screen.** The sound fixes
  above do not explain that; a notification with a bad sound still *appears*. The
  likeliest cause is that notification permission was never granted. **Check
  Settings → Riserys → Notifications first.** If "Allow Notifications" is off,
  that is the whole bug — the Grant button in onboarding never reports success
  because `requestNotificationPermission` returns before iOS answers, so it is
  easy to have skipped.
- Instrumentation was added for exactly this: the device log now prints the
  authorization state (`notDetermined` / `denied` / `authorized`, plus alert and
  sound settings), `requested=N scheduled=M cleared=S` on every reconcile, the
  pending-notification count after it, and any `center.add` failure — errors that
  were previously discarded because `add` was called without a completion handler.
  Filter the Console on `Rise[alarm]`.
- **A muted iPhone that never opens the app cannot be woken by the notification
  path.** Sounds there obey the mute switch. This is now only the iOS 16–25
  story — on 26+ AlarmKit escapes it (see above). Whether iOS below 26 is
  shippable at all is a product decision, not a bug left to fix.
- None of this is compiled — still written on Windows. Expect a first-compile
  pass on the `.caf` bundling and the new Swift.

## Shipped 2026-07-26, round 3 — the structural redesign (`feat/round3-redesign`)

(Previously: 1222 tests passing · `flutter analyze` clean · Android debug APK
builds with `--dart-define-from-file=rise.env.json` — required for every device
build, else sign-in is hidden by design.)

Rounds 1 and 2 changed states and top cards; the screen *bodies* were untouched,
which is why neither read as a redesign. This round changes the bodies. Mockups
were approved first: `docs/superpowers/specs/2026-07-26-round3-redesign-design.md`.

- **Crew is a Morning Line.** One vertical time axis with a live marker at the
  current minute. Wake-ups land above it at the minute they happened; everyone
  still under sits below with their status. This replaces the status chip strip
  AND the "Cheer them on" feed — they were the same people listed twice. The tab
  takes three shapes: **window** (live, amber, marker), **wrapped** (a record, no
  marker, misses stated as "no wake logged"), **tonight** (your own next alarm and
  its countdown). Reactions collapse to a tally plus one Cheer that opens the
  palette — six targets on a six-person morning instead of twenty-four.
- **Stats is one summary and three lenses.** The run, one plain sentence, and the
  four figures that used to live in four sections hundreds of pixels apart, now on
  one row where they can be compared. Below: Rhythm / Progress / Crew, each a
  single screenful. Nothing was deleted — every old section lives in exactly one
  lens, and only the active lens is in the widget tree.
- **A chart that answers the question.** The week chart plotted "minutes late",
  which cannot say *when do I get up*. It now plots clock time against each day's
  on-time window (`firstRingAt` → `+15 min`), so a mark inside the band is on time
  *by construction*. The 30-day `Wrap` became a Monday-first calendar, so a
  weekday pattern is visible at all.
- **Group opens on the group.** Morning → race banner → podium → rows → invite
  (was: invite first). A group of one is a share screen, not an empty leaderboard.
- **Friend opens on today.** The wake, the run it landed, and all three actions in
  the first card; mid-mission gets its own live treatment; shared groups link back
  into the app instead of dead-ending.

### Two crash bugs fixed on the way

`AsyncValue.value` **rethrows** when the provider is in an error state. Crew read
it for the account, crew, statuses, feed, voice inbox and next alarm — so a single
failed provider took the whole tab down. All reads are `valueOrNull` now.

The NOW marker originally used `AnimationController.repeat()`, which schedules a
frame every 16 ms for as long as the tab is open. It beats three times per clock
tick instead.

### Needs you (round 3)

1. **Device smoke test.** Open Crew at three different times — during your wake
   window, mid-morning, and after 21:00 — and check the tab is a different screen
   each time. The marker should sit at the current minute.
2. **Stats.** Check the four figures read together, then switch all three lenses.
   The rhythm chart needs about a week of wake-ups before it says much.
3. **Group + friend.** Open a group (morning first, invite near the end) and a
   friend (today first).
4. No new migrations, no backend changes, no new packages.

## Shipped 2026-07-26, round 2 — the visible redesign (merged to `main`)

- **Hero cards.** One inverse-ground (near-black) card per tab: Crew leads with
  the live morning ("2 of 4 up" + status-ringed faces — and a real hero when
  signed out or crew-less), Stats leads with the streak in 56px mono (count-up
  on open, last-7-mornings dots, zero state included), Profile leads with your
  identity (avatar/name/@handle) or a "Make it yours" sign-in hero.
- **Motion system.** Press-scale feedback on every touchable (`RisePressable`),
  skeleton→content crossfades (`RiseFade`), staggered section entrances on all
  tabs, date eyebrows on Crew/Stats. Reduced motion respected throughout.

## Shipped 2026-07-26 (merged to `main`)

- **Auth flash killed.** Crew/Profile briefly showed "sign in" for ~1s on open.
  The auth service now primes synchronously from the restored Supabase session +
  a persisted profile cache: a signed-in user renders signed-in on the very first
  frame. While truth is genuinely unknown, screens show neutral skeletons — never
  the sign-in hero, never the username-claim gate.
- **Per-visit spinners killed.** Feed/voice/groups/leaderboard caches now live
  for the whole session (keyed to the account id) and pre-load at app start
  (`SocialWarmupHost`); reopening Crew renders instantly and refreshes silently
  behind stale content. Skeleton placeholders (`RiseSkeleton`) replace all
  content spinners; pull-to-refresh added on Crew (reloads friendships too —
  they have no Realtime).
- **Group page deduplicated.** Leaderboard + members roster + streak-race rows
  (the same people three times) merged into ONE ranked member list: rank, avatar,
  name/@handle, on-time %, streak, Owner badge, race 🔥/💤 chip; owner's remove
  action behind a per-row "…" sheet. Score card absorbs live race status.
- **Stats rebuilt as a narrative.** Today (streak + evidence) → compact
  half-width action pair (Rough night · Share) → Overview → Your mornings
  (week chart + 30-day calendar together) → Consistency → one Alertness section
  (score + trend + disclaimer) → patterns → achievements → leaderboard (skeleton
  first-load).
- **Profile grouped.** Account card with restore-skeleton, grouped cards with
  hairline dividers (Settings/Wellbeing; Guardian; Sign out/Delete), 44px row
  targets.
- **Hardening from adversarial review:** truthful crew loading in the Supabase
  service (placeholder empty state withheld until the first load lands; a failed
  refresh keeps last-known crew), auth event-race guard (a slow profile fetch
  can no longer overwrite a newer sign-out), narrow-screen skeleton fix.

### Needs you (2026-07-26 work)

1. **Device smoke test** (2 min): open the app signed-in → Crew and Profile must
   render your account instantly, no sign-in flash, no spinner storm; second
   visit to Crew must be instant. Pull down on Crew to refresh.
2. **Group page look-over:** open a group — one member list now; owner remove is
   behind the "…" on each row; start/end a streak race and check the score card
   status line.
3. No new migrations, no backend changes, no new packages.

## Shipped 2026-07-22 (merged to `main`)

- **Left-home wake engine.** Home setup in Settings (set to current location, one tap;
  privacy tiers Off / Just me / My crew, default Off). Foreground-only departure
  detector (no background location) on app-resume within a 6h morning window,
  throttled. "Up & out" crew status on the opt-in crew tier only. Coordinates never
  leave the device — only the derived "left home" boolean is shared.
- **Wake-evidence "user card"** (top of Stats). Fuses timing, dismiss method, snoozes,
  mission slips, alertness (PVT), and left-home into a 0–100 score + a warm, non-shaming
  verdict. Each signal shown on its own line.
- **One notification system.** Collapsed the two toast styles into a single animated,
  tap-dismissable `RiseToast.show` used everywhere (was the #1 UX complaint).
- **Crew redesign** (Wave 1): mornings-together dashboard — live "this morning" strip,
  inline cheer feed, groups, add-friends in one sheet.
- **Full audit + fixes** (4 parallel lenses):
  - *Correctness:* fixed "stuck on Waking forever" after a slept-through alarm; backup
    now preserves vibration pattern; ring-path guards. Sacred alarm path verified clean.
  - *Security:* all 4 privacy invariants verified in code; no leaks; no secrets; minor
    hardening in migration `0011`. Push text stays 100% server-composed.
  - *UI/UX:* purple spinners → brand `RiseSpinner`; error→empty states now show Retry
    (`RiseErrorCard`); confirm dialogs unified; Semantics + 44px targets; reduce-motion
    honored; dead Home avatar now opens Profile.
  - *Performance:* Home no longer rebuilds every second (even while occluded); Stats
    computes aggregates once; granular `select()` rebuilds.
- **iOS parity:** all 17 native alarm-API methods implemented in Swift (contract-level;
  compile-and-fix pass needs a Mac).
- **Growth/social:** `rise://invite` group deep links via the OS share sheet; typed
  server-composed nudges (accountability ping now uses `NudgeKind.backup`).

## Needs you

1. **Apply migrations** `0010_status_out.sql` and `0011_security_hardening.sql`
   (Supabase SQL editor or `supabase db push`). Both safe on a populated DB.
2. **Redeploy** `supabase functions deploy delete-account --project-ref <ref>`.
3. **Reconnect the phone + install the APK** (Galaxy S24 Ultra wasn't connected).
   On-device passes still pending: alarm-timing feel, left-home, wake-check, branded
   notification icon.
4. **Two-account / two-device live tests:** crew "up & out" status, leaderboard sync,
   FCM nudges.

## Deferred (documented, not forgotten)

- Crew SOS UI — typed-push backend ready; placement is a product call.
- Group challenges — needs its own migration + RLS review.
- Three SQL rate-limits (username lookup, invite-code join, friend requests) —
  low priority pre-launch; see `docs/security-hardening-followups.md`.
- Bottom-sheet scrim consistency; iOS notification-budget headroom (needs the Mac pass).

See `.superpowers/sdd/progress.md` for the full per-commit ledger.
