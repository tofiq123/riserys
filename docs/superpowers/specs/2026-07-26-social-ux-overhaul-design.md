# Social UX Overhaul — auth flash, loading discomfort, Crew/Groups/Stats/Profile redesign

**Date:** 2026-07-26
**Status:** Approved (owner-mode autonomous run; user mandate: "push your limits to fix this")

## Problems (user-reported)

1. **Auth flash**: opening Crew or Profile briefly shows the signed-out UI (sign-in
   button), then flips to the signed-in UI ~1s later.
2. **Loader discomfort**: every visit to Crew shows a loading spinner.
3. **Duplication**: the same person/info is rendered multiple times on one screen
   (worst on Group detail: every member appears in the leaderboard, the members
   roster, AND the streak race — three lists of the same people).
4. **General UX**: Crew/Groups hard to parse ("what do I do, what is where");
   Stats is a monotonous wall of equally-weighted cards; Profile is a stack of
   identical rows.

## Root causes (verified by data-flow trace)

### Auth flash
- `SupabaseAuthService._current` starts **null**; `account()` yields it
  immediately, so `accountProvider` lands on `AsyncData(null)` = "signed out".
- The truthful signal — `Supabase.instance.client.auth.currentSession`, restored
  **synchronously before runApp** (see `main.dart` supabase init + the
  `_inviteSignedIn` fallback that already exploits this) — is never consulted.
- The correct account only arrives after `onAuthStateChange(initialSession)` +
  a **network** `profiles` fetch (up to 3×400ms retries) ⇒ the observed ~1s flip.
- Every consumer reads `ref.watch(accountProvider).value`, which conflates
  `AsyncLoading` and `AsyncData(null)` — "don't know yet" renders as "signed out".

### Per-visit spinner
- Tab switches unmount the whole tab subtree (`AppShell._activeTab`).
- `crewFeedProvider` and `voiceInboxProvider` are `autoDispose` ⇒ their cache
  dies with the screen; every Crew open refetches and renders `RiseSpinner`.
- All social providers are lazy: nothing loads until the first Crew/Stats visit,
  so the first open is a spinner storm.
- Loading is also conflated with empty: `crewProvider.value ?? CrewState.empty`
  renders the "no friends yet" hero while the crew list is still loading.

## Design

### 1. Auth: never guess "signed out"

**Service (`SupabaseAuthService`):**
- New `ProfileCache` (`lib/data/auth/profile_cache.dart`), backed by the same
  `SharedPreferences` instance `AppSettings` uses. Stores the last fetched
  profile as JSON `{id, username, displayName, avatarColor, email}`.
  Written on every successful profile fetch (incl. claimUsername); cleared on
  signOut/deleteAccount and on the `signedOut` auth event.
- Constructor primes synchronously from `_client.auth.currentSession?.user`:
  - no session → primed with `null` (true signed-out, emit immediately);
  - session + cache hit (matching user id) → primed with the cached account —
    first emission is the full signed-in account, **zero flash**;
  - session + cache miss → *not primed*: emit nothing until the profile fetch
    resolves, so the provider stays `AsyncLoading` (UI shows a neutral skeleton,
    never the sign-in hero, and the username-claim gate can only trigger from a
    fetch-confirmed account).
- `main.dart` constructs `SharedPreferences` once, passes it to both
  `AppSettings` and a new `profileCacheProvider` override.
- Known residual edge (pre-existing, now rarer): first-ever launch offline right
  after a sign-in that never completed a profile fetch could still misroute to
  the claim gate. Accepted; cache makes it practically unreachable.

**UI tri-state rule (Crew, Profile):**
- `AsyncLoading` with no value → neutral skeleton (new `RiseSkeleton` pulse
  placeholders, reduced-motion aware). Never the sign-in UI.
- `AsyncData(null)` → signed-out UI (unchanged heroes).
- `AsyncData(account)` → signed-in UI.

### 2. Data: stale-while-revalidate, skeletons, warmup

- Drop `autoDispose` from `crewFeedProvider` and `voiceInboxProvider`; key all
  four fetch-on-open providers (feed, voice inbox, my-groups, leaderboard) to
  the signed-in account id (`ref.watch(accountProvider.select(...))`) so a
  sign-out/sign-in swap can never leak another account's cached data.
- New `SocialWarmupHost` (matches the existing *Host pattern) mounted in the
  shell: while signed in it `ref.listen`s crew/statuses/feed/groups/voice/
  leaderboard so they load once at app start and stay alive across tab switches.
- Crew screen refreshes on open **only when data already exists**
  (`ref.invalidate` post-frame when `hasValue`): stale content renders
  instantly, fresh data lands silently (Riverpod keeps previous data during
  refresh). Pull-to-refresh added on Crew.
- Loading placeholders match final layout (skeleton chips/rows/cards) — no
  centered spinners, no layout jump. `RiseSpinner` stays for in-button busy
  states only.

### 3. Crew screen
IA stays (header → requests → This morning → Cheer them on → Groups) — it is
sound; the pain was loading behaviour. Changes: skeletons for strip/feed/groups
while first-loading, empty-states only on confirmed-empty, pull-to-refresh,
account skeleton instead of sign-in flash.

### 4. Group detail: one list, one truth
- **Merge** leaderboard standings + members roster + race rows into **one**
  "Members" list: rank, avatar, name/@handle, on-time %, streak — plus owner
  badge, a race chip (🔥 in / 💤 out) while a race runs, and the owner's remove
  action behind a per-row overflow ("…") instead of a always-visible Remove pill.
  Members without standings append unranked ("no wakes yet").
- Score card absorbs race status when one is live ("Day N · M still standing");
  "End race" becomes a small ghost action under it (owner only).
- No race → compact "Start a streak race" card (owner) or caption (member).
- Invite code compacted to one row (code + share/copy pills) — secondary once a
  group exists.
- Footer (leave/delete) unchanged.

### 5. Stats: narrative hierarchy, calmer actions
New order: streak + wake-evidence (hero) → compact half-width action pair
(Rough night? · Share) + accountability ping when present → Overview
(period metrics) → Your mornings (30-day calendar + week chart together) →
Consistency → Alertness (card + trend + disclaimer as ONE section) →
Your patterns → Achievements → Crew leaderboard (with skeleton rows while
loading). Uniform 24px section rhythm. No content removed — regrouped and
reweighted only.

### 6. Profile: grouped lists
- Account card: skeleton while auth loads (kills the sign-in flash here).
- Rows consolidated into grouped cards with internal dividers:
  "Riserys Premium" stays a standalone entry; then one card for
  Settings / Wellbeing check-in; Reliability keeps Guardian + Permissions;
  About unchanged. Delete account becomes a quieter text-row (still confirmed
  by typed DELETE).

## Testing
- TDD throughout: provider/unit tests for ProfileCache, priming logic (pure
  helper `primedAccountFrom(session user, cache)`), account-id keying, and
  non-autoDispose retention; widget tests for skeleton-not-signin during
  loading, skeleton-not-empty-hero during crew load, merged group member list
  (rank + owner + race chip + remove via overflow), Stats section order,
  Profile grouped rows. Existing 1048 tests must stay green.

## Out of scope
Backend/schema changes (none needed), Home/Alarms tab (user: "totally ok"),
iOS native, activity feed screen internals, paywall.
