# Rise — Status (overnight build, 2026-07-22)

**Verified:** 1048 tests passing · `flutter analyze` clean · Android APK builds
(`build/app/outputs/flutter-apk/app-debug.apk`). Everything below is backed by the
suite, the analyzer, or a successful compile. Live report artifact: *Rise — Overnight
Build Report*.

## Shipped (merged to `main`)

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
