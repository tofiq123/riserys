# Rise Phase 5b — Crew (friends) setup

**Prerequisite:** Phase 5a is wired and working (see `2026-07-18-supabase-setup-5a.md`) — Supabase project, Google sign-in, the `profiles` table, and a signed-in account with a claimed username. 5b adds friendships on top; it needs no new credentials or dart-defines.

## 1. Apply the migration

1. Supabase → **SQL Editor** → **New query**.
2. Paste the entire contents of `supabase/migrations/0002_friendships.sql` and **Run**.
3. Confirm:
   - **Table Editor** → a `friendships` table with RLS enabled.
   - **Database → Functions** → `find_user_by_username` and `friendships_block_reverse` exist.
   - **Database → Triggers** → `friendships_block_reverse_trg` on `friendships`.

*(CLI alternative: `supabase db push`.)*

This migration also **replaces** the 5a own-row-only `profiles` read policy with `profiles_select_own_or_crew` (own row + anyone you have a friendship with) — re-running it is safe (it drops the old policy first).

## 2. Two-account smoke test

You need two accounts (two Google accounts, or a second device / emulator). Call them **A** and **B**, each signed in with a claimed username (say `@alpha` and `@bravo`).

1. **A adds B:** on A's device, open the **Crew** tab → type `bravo` → **Find** → B's card appears → **Add**. A sees B under **Pending**.
2. **B sees the request:** on B's device, open **Crew** → B sees A under **Requests** with **Accept** / **Decline**.
3. **B accepts:** tap **Accept**. B now sees A under **Your crew**.
4. **A refreshes:** re-open A's Crew tab (5b reloads on open/action; live updates arrive in 5c) → A sees B under **Your crew**, no longer Pending.
5. **Duplicate guard:** on B's device, try to **Find** + **Add** `alpha` — you should get "Already in your crew." (the reverse-direction trigger + the app's pre-check).
6. **Remove:** on either device, **Remove** the friend → they disappear from both crews (re-open to refresh the other side).
7. **Decline path:** repeat step 1, then on B tap **Decline** → the request disappears and no friendship is created.

### What to check in the database

- After step 1: a `friendships` row `(requester=A, addressee=B, status='pending')`.
- After step 3: that row is `status='accepted'`.
- After step 6: the row is gone.
- RLS sanity: as B, you can only `select` friendships where you are requester or addressee (the SQL editor runs as the service role, so test RLS from the app, not the editor).

## Troubleshooting

- **"No one with the handle …" for a real user** — usernames are stored lowercased; the search lowercases too, so this means no `profiles` row with that username (the other user hasn't claimed one) or `find_user_by_username` didn't deploy (re-run the migration).
- **Add appears to do nothing / silent** — check that RLS `friendships_insert_own` exists and that the app is signed in (the insert uses `auth.uid()` as requester).
- **Friend shows a blank name/handle** — the `profiles_select_own_or_crew` policy didn't apply, so the crew list can't read their profile; re-run the migration and confirm the policy replaced the 5a own-row one.
- **Accept does nothing** — only the addressee can accept (`friendships_update_addressee`); make sure you're accepting on the receiving account, not the sender's.

## What's NOT in 5b (later)

Live asleep/awake status + Realtime auto-refresh (5c — 5b reloads on open/action instead), push notifications / nudges (5d), leaderboard / gifts / voice clips (5e), invite links / deep links, blocking & reporting.
