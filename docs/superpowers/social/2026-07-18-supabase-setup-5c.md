# Rise Phase 5c — Live crew status setup

**Prerequisite:** Phases 5a + 5b wired and working (accounts + crew). 5c adds live status on top; no new credentials or dart-defines.

## 1. Apply the migration

1. Supabase → **SQL Editor** → **New query**.
2. Paste the entire contents of `supabase/migrations/0003_statuses.sql` and **Run**.
3. Confirm:
   - **Table Editor** → a `statuses` table with RLS enabled.
   - **Database → Replication** (or **Database → Publications → `supabase_realtime`**) → `statuses` is included, so row changes broadcast over Realtime.

*(CLI alternative: `supabase db push`.)*

## 2. Two-account live-status smoke test

Use two accounts, **A** (`@alpha`) and **B** (`@bravo`), who are already **accepted** crew (from the 5b test). Have both apps open on the **Crew** tab.

1. **Baseline:** each sees the other in **Your crew**. A status dot appears next to a member once that member's app has published a status (it publishes on launch/resume and when their alarm state changes). If you just installed, background+foreground each app once to trigger a publish.
2. **Waking:** on B's phone, set an alarm ~1 min out and let it ring (don't dismiss yet). Within a couple seconds, **A's Crew tab should show B as "Waking"** (amber dot) — live, without A touching anything.
3. **Awake:** B dismisses the alarm. Shortly after (on B's next publish — dismissing triggers one), **A should see B flip to "Awake"** (green dot).
4. **Asleep:** if B has an enabled alarm coming within ~10h and hasn't been active for a while, B shows **"Asleep"** (indigo). (This is a heuristic — see the note below.)
5. **Legend:** the three dots under "Your crew" explain the colors.

Expected latency for a change to appear on the other device: **1–3 seconds** (Supabase Realtime).

### What to check in the database
- A `statuses` row for each signed-in user, `status` updating as their alarm state changes, `updated_at` bumping.
- RLS: from the app (not the SQL editor, which runs as service role), B can only read A's status because they're accepted crew — a non-crew user's status is not visible.

## About "asleep" (honest heuristic)

Real sleep is **not** tracked. Status is derived from alarm/wake signals:
- **waking** — an alarm is firing / being dismissed (precise).
- **awake** — dismissed within the last ~4h.
- **asleep** — a morning alarm is within ~10h and the user hasn't been active for ~8h (a presence guess, not sleep detection).
- **unknown** — none of the above → no dot.

So "asleep" means "has a morning alarm coming and hasn't been up recently," not a verified sleep state. A daytime alarm within 10h after 8h of inactivity would also read as asleep — acceptable for v1.

## Troubleshooting

- **No status dots ever appear** — the publisher only runs while signed in; make sure both apps are signed in, and background+foreground once to force a publish. Confirm `statuses` rows exist in the Table Editor.
- **Status never updates live on the other device** — `statuses` isn't in the `supabase_realtime` publication (re-run the migration; check Database → Replication).
- **A friend's dot never shows** — statuses are only visible for **accepted** friendships; confirm the friendship is accepted (not pending) in `friendships`.
- **A removed friend still shows a dot** — this shouldn't happen: the crew list is built from your friendships, so an unfriended member disappears from the list entirely (dot and all). If you ever see a stale row, re-open the Crew tab to refetch. (Separately, when an account is *deleted*, its `statuses` row is removed by cascade and the client prunes it via the Realtime delete — that path relies on `REPLICA IDENTITY FULL`, which the migration sets.)

## What's NOT in 5c (later)

Push notifications / nudges when a friend sleeps through (5d), leaderboard / gifts / voice clips (5e), an explicit "going to bed" toggle, status history, presence/last-seen.
