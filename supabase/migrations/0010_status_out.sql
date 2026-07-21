-- Rise · left-home wake signal · allow the 'out' ("up & out") status
--
-- Apply AFTER 0003_statuses.sql (Supabase SQL editor or `supabase db push`).
--
-- Design notes (PRIVACY IS THE #1 PRIORITY — read before touching):
--   * 'out' is one more coarse presence value ("up & out"), published by the
--     app ONLY when the user explicitly opted into crew sharing (the in-app
--     HomeShareTier.crew tier, default off). It is a derived boolean: no
--     coordinate, distance, radius, or home anchor is ever sent to this table
--     or anywhere else — the home anchor lives exclusively on the device.
--   * This migration ONLY widens the status CHECK constraint. The 0003 RLS
--     (own row read/write; accepted-friends-only read) is untouched and keeps
--     gating every read, including the new value. No new read surface.
--   * `statuses_status_check` is the default Postgres name for the inline
--     column check created in 0003. Existing rows all use the old values —
--     the widened set is a strict superset, so re-validation cannot fail.
--   * Idempotent: drop-if-exists + re-add; safe to re-run.

alter table public.statuses
  drop constraint if exists statuses_status_check;

alter table public.statuses
  add constraint statuses_status_check
  check (status in ('asleep', 'waking', 'awake', 'out', 'unknown'));
