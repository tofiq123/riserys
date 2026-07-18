# Phase 5e — Crew leaderboard + wake-stats sync — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A crew leaderboard ranking you + your crew by wake consistency, backed by synced aggregate wake-stats — purely additive to the local alarm app.

**Architecture:** Pure `computeWakeStats`/`rankStandings` + an injectable `LeaderboardService` (Supabase impl + a fake) make it testable without a backend. A `StatsSyncPublisher` publishes own stats on change. `leaderboardServiceProvider` gates on config. Same pattern as 5a/5b/5c.

**Tech Stack:** Flutter 3.35 / Dart 3.9, flutter_riverpod 2.6.1, supabase_flutter 2.16.0, Postgres/RLS, "Mono" design.

## Global Constraints

- **Offline-first is sacred:** stats derived from already-local wake data; publishing is best-effort and never touches the alarm/ring path. No existing local test may break.
- **Degrade gracefully:** unconfigured/signed-out → `DisabledLeaderboardService` (empty); the leaderboard section shows a sign-in prompt. Builds/runs/passes with zero credentials.
- `flutter_riverpod` 2.6.1 (2.x API only); "Mono" tokens; injectable-service + fake pattern. Usernames lowercased.
- The real `SupabaseLeaderboardService` + SQL are **build-verified + review-verified**; domain/service/providers/publisher/UI are **unit/widget-tested**.
- `database.g.dart` gitignored; `alarm_api.g.dart` committed. **TDD, teeth-first.** Branch `phase5e`.

## File Structure

- `lib/domain/wake_stats.dart` — `WakeStats` + `computeWakeStats` (Task 1).
- `lib/domain/crew_standing.dart` — `CrewStanding` + `rankStandings` (Task 1).
- `lib/data/leaderboard/leaderboard_service.dart` — interface + `FakeLeaderboardService` + `DisabledLeaderboardService` (Task 2).
- `lib/data/leaderboard/supabase_leaderboard_service.dart` — `SupabaseLeaderboardService` (Task 4).
- `lib/ui/state/leaderboard_providers.dart` — `leaderboardServiceProvider`, `leaderboardProvider` (Task 3).
- `lib/ui/stats_sync_publisher.dart` — `StatsSyncPublisher` + host (Task 5).
- `lib/ui/screens/stats_screen.dart` — the leaderboard section (Task 6).
- `lib/ui/screens/app_shell.dart` — mount `StatsSyncHost` (Task 5).
- `supabase/migrations/0004_stats.sql`, `docs/superpowers/social/2026-07-18-supabase-setup-5e.md` (Task 7).

---

## Tasks (full code written into each brief just before dispatch — same flow as 5a/5b/5c)

- **Task 1 — Domain** (`wake_stats.dart`, `crew_standing.dart`): `WakeStats{currentStreak, bestStreak, totalWakes, onTimeCount}` + `onTimeRate` + value semantics; pure `computeWakeStats(events, streak)` (streak passthrough; totals/on-time from finalized events). `CrewStanding{id, username, displayName, avatarColor, stats, isMe}` + value semantics; pure `rankStandings(list)` sorting by currentStreak desc, bestStreak desc, onTimeRate desc, username asc. Unit tests incl. tiebreaks.
- **Task 2 — `LeaderboardService` + fakes** (`leaderboard_service.dart`): interface (`publishStats`, `fetchLeaderboard`); `FakeLeaderboardService` (records `lastPublished`/count; returns a seeded list, ranked via `rankStandings`); `DisabledLeaderboardService` (no-op publish, `[]` fetch). Unit tests.
- **Task 3 — Providers** (`leaderboard_providers.dart`): `leaderboardServiceProvider` (Supabase when configured else Disabled, `ref.onDispose` if the impl needs it — it doesn't here, so no dispose); `leaderboardProvider = FutureProvider<List<CrewStanding>>` off `fetchLeaderboard()`. Provider tests with the fake.
- **Task 4 — `SupabaseLeaderboardService`** (`supabase_leaderboard_service.dart`): `publishStats` upserts `{user_id: me, current_streak, best_streak, total_wakes, on_time, updated_at}` on conflict `user_id`; `fetchLeaderboard` selects readable `stats` rows (RLS-scoped: own + accepted crew) + the matching `profiles`, maps to `CrewStanding` (isMe = row.user_id == currentUser), returns `rankStandings(...)`; best-effort. **Build-verified only** (adapt postgrest to the installed version so `flutter build apk` compiles).
- **Task 5 — `StatsSyncPublisher`** (`stats_sync_publisher.dart` + host): reads `wakeEventsProvider` + `streakProvider` (+ `accountProvider`), computes `computeWakeStats`, publishes via `publishStats` only when the stats change (deduped by value); a `StatsSyncHost` mounted in `app_shell` (alongside `StatusPublisherHost`). Tests with fakes: change → publish once; no change → none; signed-out → none.
- **Task 6 — Leaderboard UI** (`stats_screen.dart`): a "Crew leaderboard" section reading `leaderboardProvider` (+ `accountProvider`) — ranked rows (rank # + avatar + @handle + current streak; on-time rate subtitle), own row highlighted; a refresh affordance (`ref.invalidate(leaderboardProvider)`); signed-out/unconfigured → a sign-in prompt; error → retry; loading → a spinner/skeleton. Widget tests with the fake. Existing stats_screen tests still pass.
- **Task 7 — SQL + setup + verify + merge** (`0004_stats.sql`, `2026-07-18-supabase-setup-5e.md`): `stats` table + RLS (own rw; read accepted-crew only — mirror `statuses`); setup guide + two-account leaderboard smoke test. Then `flutter test` green, `flutter analyze` clean, `flutter build apk --release --dart-define-from-file=rise.env.json` builds; final whole-branch review; merge `phase5e` → `main`; device-test with the user.
