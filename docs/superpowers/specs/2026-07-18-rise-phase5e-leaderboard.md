# Rise Phase 5e — Crew leaderboard + wake-stats sync (design)

**Date:** 2026-07-18
**Status:** Drafted (build-against-the-contract; same offline-first-additive pattern as 5a/5b/5c). Builds on 5a (auth, device-verified), 5b (crew), 5c (status).
**Builds on:** the merged account + crew + status layers. Sub-project 5e of the social layer. Alarm-gifts + voice-clips are deferred (they need push/FCM — the 5d piece).

## Goal

A **crew leaderboard** ranking you and your crew by wake consistency (current streak first). Each user publishes their aggregate wake **stats**; the leaderboard reads own + accepted-crew stats and ranks them. Purely additive — nothing on the alarm path changes; the app still builds/runs with no backend.

## Non-negotiable constraints (inherited)

- **Offline-first stays sacred.** Stats are derived from local wake data that already exists; publishing is best-effort and never touches the alarm/ring path. No existing local test may break.
- **Degrades gracefully.** Unconfigured/signed-out → `leaderboardServiceProvider` yields a `DisabledLeaderboardService` (empty); the leaderboard section shows a sign-in prompt / just the user. Builds/runs/passes with zero credentials.
- `flutter_riverpod` 2.6.1; "Mono" tokens; injectable-service + fake pattern.
- The real `SupabaseLeaderboardService` + SQL/RLS are **build-verified + review-verified**; the domain/service/providers/publisher/UI are **unit/widget-tested**.

## Domain

**`WakeStats`** (`lib/domain/wake_stats.dart`): `{int currentStreak, int bestStreak, int totalWakes, int onTimeCount}`, `double get onTimeRate` (= `totalWakes == 0 ? 0 : onTimeCount / totalWakes`). Value semantics. A pure `computeWakeStats(List<WakeEvent> events, StreakStats streak)` → `WakeStats`:
- `currentStreak = streak.current`, `bestStreak = streak.best`.
- `totalWakes` = count of finalized (dismissed) events; `onTimeCount` = count of finalized events with `onTime == true`.

**`CrewStanding`** (`lib/domain/crew_standing.dart`): `{String id, String username, String displayName, String avatarColor, WakeStats stats, bool isMe}`. Value semantics. A pure `List<CrewStanding> rankStandings(List<CrewStanding>)` sorting by: `currentStreak` desc, then `bestStreak` desc, then `onTimeRate` desc, then `username` asc (stable). (Rank position = index in the sorted list.)

## Architecture

**`LeaderboardService`** (injectable interface + impls) — `lib/data/leaderboard/leaderboard_service.dart`:
```dart
abstract interface class LeaderboardService {
  Future<void> publishStats(WakeStats stats); // upsert my own stats; best-effort
  Future<List<CrewStanding>> fetchLeaderboard(); // own + accepted-crew, RANKED
}
```
- `SupabaseLeaderboardService` — upserts my `stats` row; fetches own + crew stats (join `profiles`), maps to `CrewStanding`, returns `rankStandings(...)`. **Build-verified only.** (No Realtime — a leaderboard is fetch-on-open; refresh on pull.)
- `FakeLeaderboardService` — in-memory (records published stats; returns a seeded ranked list), for tests.
- `DisabledLeaderboardService` — `publishStats` no-op; `fetchLeaderboard` returns `[]`.

Providers (`lib/ui/state/leaderboard_providers.dart`): `leaderboardServiceProvider` (Supabase when configured else Disabled); `leaderboardProvider = FutureProvider<List<CrewStanding>>` off `fetchLeaderboard()` (refreshable via `ref.invalidate`).

**`StatsSyncPublisher`** (`lib/ui/stats_sync_publisher.dart` + host): watches `wakeEventsProvider` + `streakProvider` (+ `accountProvider` to gate on signed-in), computes `computeWakeStats`, and calls `publishStats` only when the stats **change** (deduped). A `StatsSyncHost` mounted in the app shell drives it. Tested with fakes.

## Data model (Supabase) — `supabase/migrations/0004_stats.sql`

- `stats(user_id uuid primary key references auth.users on delete cascade, current_streak int not null default 0, best_streak int not null default 0, total_wakes int not null default 0, on_time int not null default 0, updated_at timestamptz not null default now())`.
- **RLS** (mirrors `statuses`): own row read/write (`for all`, `auth.uid() = user_id`); read a crew member's stats only for an **accepted** friendship (both directions). No recursion (stats reads friendships; friendships doesn't read stats). No Realtime needed (fetch-on-open).
- Upsert: `{user_id: me, current_streak, best_streak, total_wakes, on_time, updated_at: now()}` on conflict `user_id`.

## UI

- **Stats tab** (`stats_screen.dart`): a new **"Crew leaderboard"** section below the personal stats — a ranked list of `CrewStanding` rows (rank # + avatar + @handle + current streak, with on-time rate as a subtitle). The signed-in user's own row is highlighted (`isMe`). Pull-to-refresh (or a refresh affordance) re-fetches. Signed out / unconfigured → a small "Sign in to see your crew leaderboard" prompt (no leaderboard). If the crew is empty, show just the user (or an encouraging empty state).
- The alarm/home/create UI is untouched.

## Error handling

- `publishStats` failure → swallowed (best-effort).
- `fetchLeaderboard` failure → the section shows a retry affordance; never affects the alarm.

## Testing strategy

- **Domain:** `computeWakeStats` (totals/on-time/streak passthrough) + `rankStandings` (ordering incl. tiebreaks) — unit.
- **Service (fake):** `publishStats` records; `fetchLeaderboard` returns the seeded ranked list; disabled is empty/no-op.
- **Publisher:** stats change → `publishStats` once (deduped); no change → no publish; signed-out → no publish.
- **Providers:** `leaderboardProvider` reflects the fake; unconfigured → Disabled, empty.
- **UI (widget):** the ranked list renders (rank order, own row highlighted); signed-out → prompt; empty crew → just the user / empty state.
- **SQL/RLS:** review-verified + user-applied; the setup guide adds a two-account leaderboard smoke test.

## Deliverables the user applies

`docs/superpowers/social/2026-07-18-supabase-setup-5e.md`: apply `0004_stats.sql`; a two-account smoke test (both users' streaks appear ranked; adding a wake bumps the ranking on refresh).

## Out of scope (5e)

Alarm-gifts + voice-clips (need push/FCM — 5d), realtime leaderboard updates (fetch-on-open only), historical charts, per-metric leaderboards beyond the single ranking, all-time/global boards (crew-only), anti-cheat.
