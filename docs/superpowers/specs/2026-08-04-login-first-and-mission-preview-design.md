# Login-first launch flow + mission preview in the picker

**Status:** approved 2026-08-04 (brainstorm dialogue; three product decisions
confirmed: guest choice is remembered, everyone sees onboarding, premium
missions are previewable with a post-solve upsell).

## Why

Sign-in is currently the *last* onboarding page, reachable only after six
swipes, and "Continue as guest" exists only there — nothing persists the
choice, so the app has no memory of how a user arrived. The product asks for
account-optional honesty up front instead: the first screen is a login screen,
the guest path is one tap, and it sticks.

Missions are the product's differentiator, yet the picker (`MissionPickerSheet`)
is a list of labels and one-liners — a user choosing between Math and Shake is
buying blind. Every mission row gets a **Preview** button that runs the real
mission as a sandbox, then returns to the exact picker state the user left.

## Scope

In: `lib/main.dart` launch gate, `lib/data/app_settings.dart` (new flag),
`lib/ui/screens/onboarding_screen.dart` (sign-in page removed),
`lib/ui/screens/login_screen.dart` (new),
`lib/ui/missions/mission_preview_screen.dart` (new),
`lib/ui/components/mission_picker_sheet.dart` (per-row Preview),
`lib/ui/screens/create_edit_screen.dart` (wiring), plus tests.

Out: the alarm/ring path (sacred — preview is a separate host, RingScreen is
untouched), backend, migrations, packages, onboarding pages 1–6 content.

## 1 — Launch gate (`lib/main.dart`)

The single `_showOnboarding` bool becomes a three-way gate, computed once in
`_RiseAppState.initState`. All inputs are synchronous: `AppSettings`,
`SupabaseConfig.isConfigured`, and `AuthService.current` (the synchronously
primed last-known account — the same prime that killed the auth flash).

| Condition | Home |
|---|---|
| `repository == null` | `_StartupFailedPage` (unchanged) |
| Auth unconfigured **or** signed in **or** `guestChosen` | `!onboardingComplete` → `OnboardingScreen`, else `AppShell` |
| Auth configured, known signed-out, no guest flag | `LoginScreen` (new) |

Rules:

- The gate reads `ref.read(authServiceProvider).current`, never the async
  stream. Signed-in is known on the first frame, so a signed-in user can never
  see the login screen flash. "Loading is never signed-out" holds by
  construction: there is no loading state at the gate.
- **Sign-out mid-session does not bounce the app.** The user stays in the
  signed-out app (alarms keep working; Profile offers sign-in); LoginScreen
  returns on the next cold start. Yanking the UI on sign-out would be hostile
  in an app that is fully usable signed-out.
- Successful sign-in clears `guestChosen`; the guest CTA sets it. So: sign out
  → next launch shows login; guest once → login never appears again unless the
  user later signs in and signs out.
- Cold-start ring override is untouched: a ringing alarm still pushes
  `RingScreen` over whatever the gate chose.

New flag in `AppSettings`: `guestChosen` (SharedPreferences key
`'guestChosen'`, default `false`), with `setGuestChosen(bool)`.

## 2 — `LoginScreen` (new: `lib/ui/screens/login_screen.dart`)

One screen, two ways forward, no skip (guest *is* the skip). Built from
existing primitives (`PrimaryButton`, `GhostButton`, tokens/typography),
modelled on the onboarding sign-in page it replaces:

- Centred brand mark (rounded-square accent container, sunrise glyph),
  "Welcome to Riserys" title, one honest line: *"Sign in to back up your
  streak and wake with your crew — or keep going solo."*
- `PrimaryButton` **Sign in with Google** with the existing signing-in
  spinner + double-tap guard pattern. On success: clear `guestChosen`, advance
  the gate (onboarding if incomplete, else AppShell). On cancel/failure: error
  toast, stay put — same copy as today ("Sign-in didn't complete. Try again,
  or continue as guest.").
- `GhostButton` **Continue as guest**: set `guestChosen`, advance the gate.
- Small print under the CTAs: *"Alarms always work without an account."*

The screen takes an `onAdvance` callback from the gate (like onboarding's
`onDone`) so it stays navigation-free and widget-testable.

## 3 — Onboarding loses its sign-in page

- `_signInStep` / `_signInPage` / `_signInAndFinish` are removed from
  `onboarding_screen.dart`. The flow ends on the permissions page for
  everyone — exactly as it already does when auth is unconfigured. Pages 1–6
  (intros, intention, sleep goal, first alarm, permissions) are unchanged.
- "Continue as guest" no longer exists inside onboarding; the choice lives
  exclusively on LoginScreen.
- Net effect: onboarding is a pure product tour + setup wizard, identical for
  signed-in and guest users (approved decision: everyone sees onboarding).

## 4 — Mission preview

### In the picker (`mission_picker_sheet.dart`, stays Riverpod-free)

- Every mission row except `none` gets a trailing **Preview** text button
  (44 px target, caption style, left of the lock/check glyphs). `none` has
  nothing to try — it is just slide-to-wake.
- `showMissionPickerSheet` gains one injected callback:
  `onPreview(Alarm preview)`. The sheet synthesises the preview alarm
  look-don't-touch:
  - `mission` = the row's key (any row, not just the selected one);
  - `missionDiff` = the picker's current difficulty;
  - `missionCount` = 1 always (a preview demonstrates the mechanic, not the
    endurance);
  - `missionData` carried over only when previewing the currently selected
    `qr`/`photo` mission, so a real registration is honoured and a stale one
    can never leak across missions.
- Previewing never mutates `_draft`. Selection, scroll and config are exactly
  as left when the user returns.

### The preview screen (new: `lib/ui/missions/mission_preview_screen.dart`)

- A lightweight sandbox host — deliberately **not** `RingScreen`: no alarm
  audio, no snooze, no wake recording, no platform alarm calls.
- Same dark ground as the ring screen so missions render as designed. Top
  chrome: "PREVIEW" eyebrow + mission label + an "End preview" close. Hosts
  the mission via the existing `buildMission`, so every mission runs its real
  widget; camera missions request permissions through their existing in-widget
  flows, same as in ring.
- **Solved → completion card**, two shapes:
  - Free/unlocked: check, *"Solved — that's {label} on {difficulty}."*
    (the difficulty clause is omitted for `qr`/`photo`, which take none),
    primary **Back to missions**.
  - Premium-locked (approved teaser): the same solved line + an upsell block —
    *"Unlock Premium to wake with {label}."* + **See Premium** (fires the
    injected `onOpenPaywall`) + ghost **Back to missions**.
- `alarm`, `locked` and `onOpenPaywall` are constructor-injected; the screen
  is widget-testable with fakes, like the sheet.

### Return to the exact place

The preview is pushed as a route **over** the open sheet (using the outer
`BuildContext` already passed to `showMissionPickerSheet`). The sheet route
stays mounted underneath, so scroll offset, selected mission, difficulty,
repeat and registrations are preserved by the Navigator. "Back to where you
left" is a pop — by construction, not by hand-restored state.

## 5 — Edge cases and error handling

- Sign-in failure/cancel on LoginScreen → toast, stay; the guest CTA is always
  live (never trapped).
- Auth unconfigured (missing `rise.env.json`) → LoginScreen never appears;
  alarms unaffected.
- Reinstall / cleared data while signed in → `onboardingComplete=false` +
  known account → straight to onboarding, never login.
- Existing signed-out users on upgrade → see LoginScreen once; one tap on
  guest dismisses it forever. This is the one behaviour change for current
  users and is intentional.
- QR/photo preview with nothing registered → the mission accepts any
  scan/photo, identical to ring behaviour (anti-trap, already the rule).
- Permission denial inside a camera-mission preview → the mission's existing
  denial UI shows; "End preview" always works.
- Preview records nothing: no wake event, no alertness score (PVT's
  `onAlertness` is not wired in preview), no stats, no entitlement change.

## 6 — Testing

- `test/data/app_settings_test.dart`: `guestChosen` default / set / persist.
- New `test/ui/screens/login_screen_test.dart`: both CTAs render; guest sets
  the flag + advances; sign-in success clears the flag + advances; failure →
  toast + stays; double-tap guard.
- Gate tests at the RiseApp level: signed-out → login; guest flag → skips to
  onboarding/shell; signed-in → skips login; unconfigured auth → login never
  shown.
- `test/ui/screens/onboarding_screen_test.dart`: sign-in page gone;
  configured and unconfigured flows identical; no guest CTA anywhere in
  onboarding.
- `test/ui/components/mission_picker_sheet_test.dart`: Preview on every row
  except `none`; the callback receives the correctly synthesised alarm;
  `_draft` untouched by preview.
- New `test/ui/missions/mission_preview_screen_test.dart`: mission hosts and
  solves → free completion card; locked → upsell + paywall callback; both exit
  paths pop.
- Round-trip widget test: open sheet → scroll → select → preview → pop →
  assert sheet state (selection + scroll) intact.
- Gates: `flutter analyze` clean; the full suite (1222 tests + new) green.

## Invariants honoured

- **The alarm path is sacred.** Ring, dismiss, snooze and scheduling are
  untouched; preview is a separate host that never records.
- **No account must never break an alarm.** LoginScreen is skipped entirely
  when the backend is unconfigured; the guest CTA never depends on the
  network; sign-out never yanks the UI.
- **Loading is never signed-out.** The gate reads the synchronously primed
  `AuthService.current`; there is no async auth read at launch.
- **Wellness, not medical.** Preview wires no alertness recording; the PVT
  score and its disclaimer stay where they live today.
- Riverpod stays pinned at 2.6.1; no new packages, migrations, or backend
  changes.
