# Phase 5b — Crew (friends) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the placeholder Crew tab into a real friends feature (add by username, send/accept/decline/cancel requests, see and remove crew), backed by a Supabase `friendships` table with RLS — purely additive to the local alarm app.

**Architecture:** An injectable `CrewService` (Supabase impl + a fake) makes the whole friendship state machine testable without a backend. `crewServiceProvider` gates on `SupabaseConfig.isConfigured` (unconfigured → `DisabledCrewService`). A `friendships` table + a `find_user_by_username` RPC + a broadened profiles-read policy back it. Same pattern as 5a.

**Tech Stack:** Flutter 3.35 / Dart 3.9, flutter_riverpod 2.6.1, supabase_flutter 2.16.0, Postgres/RLS, "Mono" design.

## Global Constraints

- **Offline-first is sacred:** the alarm/ring/snooze/stats path never touches crew or the network. No existing local test may break.
- **Degrade gracefully:** unconfigured/signed-out → `DisabledCrewService` (empty, no writes); the Crew tab shows a "sign in from Profile to build your crew" prompt. Only a signed-in configured user sees the crew UI. The app builds + runs + passes all tests with zero credentials.
- `flutter_riverpod` 2.6.1 (2.x API only); "Mono" design tokens; injectable-service + fake pattern.
- Usernames lowercased (matches 5a). The real `SupabaseCrewService` + SQL are **build-verified + review-verified**; interface/fake/providers/UI are **unit/widget-tested** via `FakeCrewService`.
- `database.g.dart` stays gitignored; `alarm_api.g.dart` stays committed. **TDD, teeth-first.** Branch `phase5b`.

## File Structure

- `lib/domain/crew_member.dart` — `CrewMember` (Task 1).
- `lib/domain/crew_state.dart` — `CrewState` (Task 1).
- `lib/data/crew/crew_service.dart` — interface + `FakeCrewService` + `DisabledCrewService` + exceptions (Task 2).
- `lib/data/crew/supabase_crew_service.dart` — `SupabaseCrewService` (Task 4).
- `lib/ui/state/crew_providers.dart` — `crewServiceProvider`, `crewProvider` (Task 3).
- `lib/ui/screens/crew_screen.dart` — the Crew tab (Task 5).
- `lib/ui/screens/app_shell.dart` — swap the `_ComingSoon` Crew case for `CrewScreen` (Task 5).
- `supabase/migrations/0002_friendships.sql` — table + RLS + RPC + broadened profiles read (Task 6).
- `docs/superpowers/social/2026-07-18-supabase-setup-5b.md` — setup addendum (Task 6).

---

## Tasks (full code written into each brief just before dispatch — same flow as 5a)

- **Task 1 — Domain** (`crew_member.dart`, `crew_state.dart`): `CrewMember{id, username, displayName, avatarColor}` + value semantics + `copyWith`; `CrewState{friends, incoming, outgoing}` + `const CrewState.empty` + value equality + a `bool get isEmpty`. Unit tests.
- **Task 2 — `CrewService` + fakes** (`crew_service.dart`): the interface (from the spec) + `UserNotFoundException`/`FriendshipException`; `FakeCrewService` (seedable directory of `CrewMember`s + initial `CrewState`; `sendRequest` moves a member to outgoing and throws on self/duplicate/existing; `acceptRequest` moves incoming→friends; `declineRequest`/`cancelRequest`/`removeFriend` remove; `findByUsername` against the directory; a broadcast `watch()` that yields current then changes; a `dispose`); `DisabledCrewService` (empty, writes throw `StateError('crew not configured')`). Unit tests over the fake's state machine.
- **Task 3 — Providers** (`crew_providers.dart`): `crewServiceProvider` returns `SupabaseCrewService` when configured else `DisabledCrewService` (with `ref.onDispose`); `crewProvider = StreamProvider<CrewState>`. Provider tests with the fake.
- **Task 4 — `SupabaseCrewService`** (`supabase_crew_service.dart`): queries `friendships` (`.or('requester.eq.$me,addressee.eq.$me')`) + `profiles` (`.inFilter('id', otherIds)`), buckets into friends/incoming/outgoing; `findByUsername` via `rpc('find_user_by_username')`; mutations insert/update/delete then re-load; a broadcast controller primed on construction (auth-scoped). **Build-verified only** (compiles + `flutter build apk --debug` unconfigured). Adapts the exact postgrest API to the installed version.
- **Task 5 — Crew tab UI** (`crew_screen.dart` + `app_shell.dart`): not-signed-in prompt; signed-in add-by-username (resolve→add), Requests (accept/decline), Your crew (remove), Pending (cancel). Reads `crewProvider` + `accountProvider`. Swap the `_ComingSoon` Crew case for `CrewScreen`. Widget tests with the fake across states; `app_shell_test` still green (default crew empty).
- **Task 6 — SQL migration + setup addendum** (`0002_friendships.sql`, `2026-07-18-supabase-setup-5b.md`): the friendships table + RLS + `find_user_by_username` RPC + broadened `profiles_select_own_or_crew` policy; a two-account Crew smoke test. Review-verified.
- **Task 7 — Verify + merge:** `flutter test` green, `flutter analyze` clean, `flutter build apk --release` (unconfigured) builds; final whole-branch review; merge `phase5b` → `main`.
