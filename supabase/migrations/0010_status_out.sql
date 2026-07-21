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
--   * The 0003 check was created INLINE (unnamed), so its name is whatever
--     Postgres auto-generated (normally `statuses_status_check`). A drop by
--     that literal name would silently no-op if the name ever differed — and
--     the old check would then keep rejecting 'out'. So the drop below finds
--     every CHECK constraint on the table via the catalog instead of trusting
--     a name. Existing rows all use the old values — the widened set is a
--     strict superset, so re-validation cannot fail.
--   * Idempotent: the catalog loop also drops the named constraint this
--     migration adds, so re-running is safe.

do $$
declare
  c record;
begin
  for c in
    select conname
    from pg_constraint
    where conrelid = 'public.statuses'::regclass
      and contype = 'c'
  loop
    execute format('alter table public.statuses drop constraint %I', c.conname);
  end loop;
end $$;

alter table public.statuses
  add constraint statuses_status_check
  check (status in ('asleep', 'waking', 'awake', 'out', 'unknown'));
