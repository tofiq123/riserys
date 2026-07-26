# Rise — Status (social UX overhaul + bold redesign, 2026-07-26)

**Verified:** 1106 tests passing · `flutter analyze` clean · Android APK builds and
is INSTALLED on the test phone (built with `--dart-define-from-file=rise.env.json` —
required for every device build, else sign-in is hidden by design).

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
