# Rise Phase 5b — Crew (friends) (design)

**Date:** 2026-07-18
**Status:** Drafted autonomously (build-against-the-contract; same offline-first-additive pattern as 5a). Builds on Phase 5a (merged `7a6849e`).
**Builds on:** the merged account foundation (5a). This is sub-project 5b of the social layer; live status (5c), push/nudges (5d), leaderboard/gifts (5e) are later specs.

## Goal

Turn the placeholder **Crew** tab into a real friends feature: add friends by username, send/accept/decline/cancel requests, see your crew, and remove friends. Backed by a Supabase `friendships` table with RLS. Purely additive — nothing on the alarm path changes, and the app still builds/runs with no backend.

## Non-negotiable constraints (inherited from 5a)

- **Offline-first stays sacred.** No alarm/ring/snooze/stats code touches the network or depends on crew.
- **Degrades gracefully.** Unconfigured → `crewServiceProvider` yields `DisabledCrewService` (empty crew, no writes); the Crew tab shows a "sign in to build your crew" prompt. Signed out (but configured) → same prompt (Profile has the sign-in button). Only a signed-in, configured user sees the crew UI.
- **Google-only auth** (from 5a); `flutter_riverpod` 2.6.1; injectable-service + fake pattern; "Mono" tokens.
- The real `SupabaseCrewService` and the SQL/RLS are **build-verified + review-verified** (no live backend in CI); the interface, fake, providers, and UI are **unit/widget-tested** via `FakeCrewService`.

## Architecture

**`CrewMember`** (`lib/domain/crew_member.dart`): the public view of another user — `{id, username, displayName, avatarColor}`. Immutable, `==`/`hashCode`/`copyWith`. (No email — that's private to the account owner.)

**`CrewState`** (`lib/domain/crew_state.dart`): `{List<CrewMember> friends, List<CrewMember> incoming, List<CrewMember> outgoing}` — accepted friends; incoming pending requests (I am the addressee, I can accept/decline); outgoing pending requests (I am the requester, I can cancel). `const CrewState.empty`. Value equality.

**`CrewService`** (injectable interface + impls) — `lib/data/crew/crew_service.dart`:
```dart
abstract interface class CrewService {
  Stream<CrewState> watch();          // emits current on listen + after each change
  CrewState get current;
  Future<CrewMember?> findByUsername(String username); // resolve for the add flow; null if none
  Future<void> sendRequest(String userId);
  Future<void> acceptRequest(String userId);   // accept an incoming request
  Future<void> declineRequest(String userId);  // decline an incoming request
  Future<void> cancelRequest(String userId);   // cancel my outgoing request
  Future<void> removeFriend(String userId);
}
```
- `SupabaseCrewService` — production. Queries `friendships` (joined to `profiles`), resolves usernames via a `find_user_by_username` RPC, and re-loads after each mutation (Realtime is 5c). **Build-verified only.**
- `FakeCrewService` — in-memory, seedable with a directory of known members + an initial state, for unit/widget tests.
- `DisabledCrewService` — used when unconfigured/signed-out: `current == CrewState.empty`, streams empty, writes throw a clear "not configured".

Providers (`lib/ui/state/crew_providers.dart`): `crewServiceProvider` returns `SupabaseCrewService` when `SupabaseConfig.isConfigured` else `DisabledCrewService` (overridable with the fake); `crewProvider = StreamProvider<CrewState>` off `watch()`.

`UserNotFoundException` and a `CrewException` (or reuse a clear error) surface add-flow failures (already-friends, self-add, duplicate request).

## Data model (Supabase) — `supabase/migrations/0002_friendships.sql`

- `friendships(id uuid pk default gen_random_uuid(), requester uuid → auth.users on delete cascade, addressee uuid → auth.users on delete cascade, status text default 'pending' check in ('pending','accepted'), created_at timestamptz default now(), check(requester <> addressee), unique(requester, addressee))`. Indexes on requester and addressee.
- **RLS:** select rows where you are requester or addressee; insert only as the requester with status 'pending'; update only by the addressee (accept: pending→accepted); delete by either party (decline/cancel/remove).
- **Broaden `profiles` read:** replace `profiles_select_own` with `profiles_select_own_or_crew` — a profile is readable if it's your own OR a friendship (pending or accepted) exists between you and it. Lets crew lists show handles/names/avatars. (No recursion: the profiles policy's subquery reads `friendships`, which doesn't read `profiles`.)
- **`find_user_by_username(name text)`** — SECURITY DEFINER, `search_path=''`, returns `table(id, username, display_name, avatar_color)` for the one matching (lowercased) username. Lets a signed-in user resolve a username to send a request **before** any friendship (and thus profiles-read) exists. `revoke from public` / `grant execute to authenticated`.

## UI — Crew tab (`lib/ui/screens/crew_screen.dart`, replaces the `_ComingSoon` case in `app_shell.dart`)

- **Not signed in** (account null / unconfigured): a friendly empty state — "Wake up with your crew. Sign in from the Profile tab to add friends." (No sign-in button here; Profile owns it.)
- **Signed in:**
  - **Add by username** — a row/button opening an inline field or sheet: type a username → resolve (`findByUsername`) → show the found member (or "no one with that handle") → **Add** sends the request.
  - **Requests** section (only if `incoming` non-empty): each incoming member with **Accept** / **Decline**.
  - **Your crew** section: accepted friends, each with a **Remove** affordance; empty → "No crew yet. Add friends by username."
  - **Pending** section (only if `outgoing` non-empty): each outgoing member with **Cancel**.
- All crew UI reads `crewProvider` + `accountProvider`; the alarm/home/stats UI is untouched.

## Error handling

- `findByUsername` returns null → inline "No one with that handle." No crash.
- `sendRequest` to yourself / an existing friend / a duplicate → surfaced inline (toast/snackbar), state unchanged.
- Any network error → surfaced, retryable; never touches the alarm path.

## Testing strategy

- **Domain:** `CrewMember`/`CrewState` value semantics (unit).
- **Service state machine (fake):** send → appears in outgoing; the other side sees incoming; accept → both see a friend; decline/cancel/remove → removed; `findByUsername` hit/miss; self/duplicate guarded. All via `FakeCrewService`.
- **Providers:** `crewProvider` reflects the fake's stream; unconfigured → `DisabledCrewService`, empty.
- **UI (widget):** not-signed-in shows the prompt; signed-in shows crew/requests/pending; add-by-username resolves + sends; accept/decline/cancel/remove call the service.
- **SQL/RLS:** review-verified + user-applied; the setup guide gains a Crew smoke test.

## Deliverables the user applies

Append to the 5a setup guide (or a `2026-07-18-supabase-setup-5b.md` addendum): apply `0002_friendships.sql`; a two-account smoke test (A adds B by username → B sees the request → B accepts → both see each other in crew → remove).

## Out of scope (5b)

Invite links / deep links (need native deep-link config — later), live asleep/awake status + Realtime (5c), push/nudges (5d), leaderboard/gifts/voice clips (5e), blocking/reporting, crew size limits. Add-by-username is the only add mechanism in 5b.
