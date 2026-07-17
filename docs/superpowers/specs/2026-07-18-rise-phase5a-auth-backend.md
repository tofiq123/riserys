# Rise Phase 5a — Auth + backend foundation (design)

**Date:** 2026-07-18
**Status:** Drafted from brainstorming (build-against-the-contract; Google-only for now; offline-first additive auth — approved by user); pending user spec review.
**Builds on:** the merged Android app (Plans 1–3, Phase 4a/4b). This is the FIRST networked feature. It is **sub-project 5a** of the social layer; Crew (5b), live status (5c), push/nudges (5d), and leaderboard/gifts (5e) are separate later specs that build on this foundation.

## Goal

Add an **optional account** to Rise, backed by Supabase: Google sign-in, a `profiles` row with a claimed username, and account management (sign out, delete account). Signing in unlocks the social layer (built later); staying signed out is the full app as it exists today.

## Non-negotiable constraints

- **Offline-first stays sacred.** The alarm, ring, snooze, missions, streaks/stats, and all local features work with **no account and no network**. Nothing on the alarm/ring path ever awaits the network. Auth is purely additive.
- **Degrades gracefully when unconfigured.** With no Supabase/Google credentials supplied, the app runs exactly as it does today — Supabase never initializes and the "Sign in" affordance is hidden. Credentials are supplied at build via `--dart-define` (so nothing secret lives in the repo).
- **Google-only** sign-in for now (native on Android). Apple Sign-In is added with the iOS engine.
- `flutter_riverpod` 2.6.1; design tokens; the established injectable-service + fake pattern (like `PermissionGateway`).

## Configuration

```dart
class SupabaseConfig {
  static const url = String.fromEnvironment('SUPABASE_URL');
  static const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
  static bool get isConfigured =>
      url.isNotEmpty && anonKey.isNotEmpty && googleServerClientId.isNotEmpty;
}
```
`main()` initializes Supabase **only if** `isConfigured`. Build with credentials via:
`flutter build apk --dart-define=SUPABASE_URL=… --dart-define=SUPABASE_ANON_KEY=… --dart-define=GOOGLE_SERVER_CLIENT_ID=…`

## Architecture

**`AuthService` (injectable interface + two impls).** The whole sign-in/session/username state machine is testable without a live backend:

```dart
abstract interface class AuthService {
  Stream<RiseAccount?> account();          // emits on auth-state change; null = signed out
  RiseAccount? get current;
  Future<void> signInWithGoogle();
  Future<bool> isUsernameAvailable(String username);
  Future<void> claimUsername(String username, {required String displayName});
  Future<void> signOut();
  Future<void> deleteAccount();
}
```
- `SupabaseAuthService` — production. Google native sign-in (`google_sign_in` with `serverClientId`) → `supabase.auth.signInWithIdToken(provider: google, …)`; reads/writes the `profiles` row; `deleteAccount` calls an edge function or an RPC that removes the auth user + row.
- `FakeAuthService` — in-memory, for unit/widget tests.
- `DisabledAuthService` — used when `!isConfigured`: `current == null`, streams `null`, and sign-in throws a clear "not configured" (never reached because the UI hides sign-in).

Provider: `authServiceProvider` returns the impl chosen by `SupabaseConfig.isConfigured` (overridable in tests with the fake). `accountProvider` = `StreamProvider<RiseAccount?>` off `account()`.

**`RiseAccount`** (`lib/domain/rise_account.dart`): `id`, `username` (nullable — null means "not yet claimed"), `displayName`, `avatarColor`, `email?`. Immutable, `==`/`hashCode`/`copyWith`.

**Sign-in flow:** tap Sign in → `signInWithGoogle()` → Supabase session established → `account()` emits a `RiseAccount` with `username == null` if there's no `profiles` row → the UI routes to the **username-claim** screen → `claimUsername` (uniqueness-checked) inserts the row → `account()` re-emits with the username set. A returning user (row exists) skips the claim.

## Data model (Supabase)

`supabase/migrations/0001_profiles.sql`:
- Table `profiles`: `id uuid primary key references auth.users(id) on delete cascade`, `username text unique not null`, `display_name text not null default ''`, `avatar_color text not null default '…'`, `tz text`, `created_at timestamptz default now()`. A `check` on username format (3–20 chars, `[a-z0-9_]`).
- **RLS enabled.** Policies for 5a: a user may `select`/`insert`/`update` **only their own row** (`id = auth.uid()`). (Broader read — needed to see friends — is added in 5b with the friendships table, so we don't over-grant now.)
- Username uniqueness is the DB `unique` constraint; `isUsernameAvailable` is a `select` count (racy check for UX only — the `unique` constraint is the real guard, and `claimUsername` surfaces a "taken" error if the insert conflicts).
- `deleteAccount`: an edge function `delete-account` (or a `security definer` RPC) that deletes the auth user (cascade removes the profile). Provided as SQL/TS to deploy.

## UI

- **Profile screen** (`profile_screen.dart`): the "Guest" card becomes account-aware. Signed out + configured → a "Sign in with Google" button. Signed in → the username + avatar-color chip, and a **Sign out** + **Delete account** (with a typed/confirmed guard) row. Unconfigured → the current guest card unchanged (no sign-in shown).
- **Username-claim screen** (`username_claim_screen.dart`): a text field (live-validated format + availability), a display-name field, and a "Claim" button; shown after sign-in when `username == null`. Cannot be skipped (a username is required to be social), but the user can sign out to back out.
- All account UI reads `accountProvider`; the alarm/home/stats UI is untouched (they never depend on an account).

## Error handling

- Sign-in cancelled/failed → a toast, stays signed out; the local app is unaffected.
- Network error during claim → surfaced inline; retryable.
- `deleteAccount` → typed confirmation; on success signs out to the local app.
- All auth calls are outside any alarm path; a total Supabase outage only disables social, never the alarm.

## Testing strategy

- **Config gate:** `SupabaseConfig.isConfigured` truth table (unit).
- **Auth state machine (fake):** sign-in emits an account; a no-username account routes to claim; claim emits the username; sign-out emits null; delete emits null; username availability + a taken-on-claim conflict. All via `FakeAuthService` (no network).
- **UI (widget):** Profile shows Sign-in when signed out + configured, the account + sign-out/delete when signed in, and the unchanged guest card when unconfigured; the username-claim screen validates format/availability and calls `claimUsername`.
- **SQL/RLS:** review-verified and **user-applied**; a later increment can add Supabase-local (Docker) integration tests. The setup guide includes a manual smoke test (sign in on device → a `profiles` row appears).

## Deliverables the user applies (with a click-by-click guide)

`docs/superpowers/social/2026-07-18-supabase-setup-5a.md`:
1. Create a free Supabase project → copy the **Project URL** + **anon key**.
2. Google Cloud: OAuth consent screen + an **Android** OAuth client (package `com.riseapp.rise` + the release/debug SHA-1) + a **Web** OAuth client (its client ID is the `GOOGLE_SERVER_CLIENT_ID` used for `signInWithIdToken`).
3. Supabase → Auth → Providers → enable **Google**, paste the Web client ID/secret.
4. Apply `supabase/migrations/*.sql` (SQL editor or `supabase db push`).
5. Build with the three `--dart-define`s; sign in on device; confirm a `profiles` row appears.

## Out of scope (5a)

Crew/friendships, live status, push/FCM, nudges, leaderboard, stats/wake-event cloud sync, alarm gifts, voice clips, RevenueCat — all later sub-plans. Apple + email sign-in. Any change to the local alarm engine.
