# Rise Phase 5e — Crew leaderboard setup

**Prerequisite:** Phases 5a + 5b + 5c wired and working (accounts + crew + status). 5e adds a leaderboard; no new credentials or dart-defines.

## 1. Apply the migration

1. Supabase → **SQL Editor** → **New query**.
2. Paste the entire contents of `supabase/migrations/0004_stats.sql` and **Run**.
3. Confirm: **Table Editor** → a `stats` table with RLS enabled.

*(CLI alternative: `supabase db push`.)*

Unlike `statuses`, the `stats` table is **not** added to Realtime — the leaderboard fetches on open (pull to refresh with the ↻ icon).

## 2. Two-account leaderboard smoke test

Two accounts **A** (`@alpha`) and **B** (`@bravo`), already **accepted** crew.

1. **Publish:** each app publishes its own stats on launch/resume and whenever wake data changes. If you just installed, open each app and background+foreground once to force a publish. Confirm in **Table Editor → stats** that a row appears for each user.
2. **Leaderboard:** on A's phone → **Stats** tab → scroll to **"Crew leaderboard"**. You should see both **A** and **B**, ranked by current streak (A's own row is highlighted).
3. **Climb:** have B wake up on time a few days (or seed some `wake_events`) so B's `current_streak` rises; tap the **↻** refresh on A's leaderboard → B moves up the ranking.
4. **Ranking rule:** current streak desc, then best streak, then on-time %, then username. The "N% on time" subtitle and "day streak" come straight from each user's synced stats.

### What to check in the database
- A `stats` row per user with `current_streak`/`best_streak`/`total_wakes`/`on_time` updating as their wake data changes, `updated_at` bumping.
- RLS: from the app (not the SQL editor, which runs as service role), A can only read B's stats because they're accepted crew — a non-crew user's stats are not visible.

## Troubleshooting

- **Leaderboard shows only you** — your crew hasn't published stats yet (they need to open their app at least once), or the friendship isn't accepted. Confirm `stats` rows exist for them and the friendship is `accepted`.
- **"Sign in from the Profile tab to rank up"** — you're signed out; the leaderboard needs an account.
- **"Could not load the leaderboard"** — a fetch error; tap **Retry**. Confirm `0004_stats.sql` ran and RLS is enabled.
- **A crew member is missing** — stats are only readable for **accepted** friendships; a pending request doesn't share stats. Also, a member with no `stats` row (never opened the app) won't appear.
- **Streak looks stale** — stats publish on wake-data change + app resume; pull the ↻ refresh, or background+foreground the other person's app to force their publish.

## What's NOT in 5e (later)

Alarm-gifts + voice-clips (need push/FCM — 5d), realtime leaderboard updates (fetch-on-open only), all-time/global boards, historical charts, per-metric leaderboards.
