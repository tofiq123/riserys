-- Rise · Account sync · per-account alarm + wake-history backup (table + RLS)
--
-- Apply AFTER 0001-0007 (Supabase SQL editor or `supabase db push`).
--
-- Design notes (SECURITY IS THE #1 PRIORITY — read before touching a policy):
--   * Alarms + wake-history are LOCAL-first (device Drift is the source of truth).
--     This table is a single-row-per-user cloud BACKUP so a reinstall / fresh
--     device can restore. `payload` is an opaque JSON blob the client owns
--     (shape `{ "v": 1, "alarms": [...], "wakeEvents": [...] }`); the server
--     never reads inside it, so no columns/constraints depend on its contents.
--   * One row per user (user_id is the PK and the FK to auth.users). The client
--     UPSERTs on user_id, so the row is created on first push and replaced on
--     every later push — there is never more than one backup per account.
--   * Single-owner row: a user may only ever touch their OWN row. All four
--     policies are the same `user_id = auth.uid()` predicate — no cross-table
--     lookups, so no SECURITY DEFINER helpers and no recursion (unlike 0006).
--   * ON DELETE CASCADE from auth.users: deleting the account drops the backup,
--     matching the "delete account" promise in 0001-0005.
--
-- Build-verified only: no live backend in CI. The restore path is exercised by
-- the reinstall smoke test in the account-sync setup guide.


-- ─────────────────────────────────────────────────────────────────────────────
-- Table
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.account_backups (
  user_id    uuid        primary key references auth.users (id) on delete cascade,
  payload    jsonb       not null,
  updated_at timestamptz not null default now()
);

alter table public.account_backups enable row level security;


-- ─────────────────────────────────────────────────────────────────────────────
-- RLS · account_backups. Every action is scoped to the caller's own row; a user
-- can neither read nor write anyone else's backup. All four are explicit so the
-- client's upsert (INSERT ... ON CONFLICT DO UPDATE) is covered by both the
-- INSERT and the UPDATE policy.
-- ─────────────────────────────────────────────────────────────────────────────

-- SELECT: only your own backup row (used by restore()).
drop policy if exists account_backups_select_own on public.account_backups;
create policy account_backups_select_own on public.account_backups for select
  using (user_id = auth.uid());

-- INSERT: only a row keyed to yourself (first push creates it).
drop policy if exists account_backups_insert_own on public.account_backups;
create policy account_backups_insert_own on public.account_backups for insert
  with check (user_id = auth.uid());

-- UPDATE: only your own row (every later push replaces the payload).
drop policy if exists account_backups_update_own on public.account_backups;
create policy account_backups_update_own on public.account_backups for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- DELETE: only your own row.
drop policy if exists account_backups_delete_own on public.account_backups;
create policy account_backups_delete_own on public.account_backups for delete
  using (user_id = auth.uid());
