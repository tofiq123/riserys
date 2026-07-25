-- Rise · Security hardening · per-caller rate limits
--
-- Apply AFTER 0001–0011 (Supabase SQL editor or `supabase db push`). Idempotent.
--
-- Closes the three "at scale" abuse vectors from docs/security-hardening-followups.md:
--   * find_user_by_username (0002) — directory harvesting of profiles
--   * join_group_by_code   (0006) — brute-forcing 6-char invite codes
--   * friend-request insert (0002) — outgoing request spam
--
-- Design (SECURITY DEFINER, empty search_path, schema-qualified — mirrors 0002/0006):
--   * rate_events(actor, action, at) records one row per rate-limited action.
--     RLS is ON with NO policies, so no client can read or write it directly;
--     only the SECURITY DEFINER check_rate() (which runs as owner and bypasses
--     RLS) touches it.
--   * check_rate(action, max, window) — called at the top of each protected path.
--     It opportunistically prunes this caller's expired rows, counts the rest in
--     the window, RAISES with SQLSTATE 'PT429' if at/over the cap, else records
--     the event. auth.uid() is the caller even inside SECURITY DEFINER (the JWT
--     claim GUC is unchanged by definer context — same pattern as create_group).
--   * Thresholds are deliberately generous so a real user is never locked out;
--     tune against live usage before a public launch.


-- ─────────────────────────────────────────────────────────────────────────────
-- rate_events + check_rate
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.rate_events (
  actor  uuid        not null references auth.users (id) on delete cascade,
  action text        not null,
  at     timestamptz not null default now()
);

-- Covers the "my events for this action in the window" scan check_rate runs.
create index if not exists rate_events_lookup_idx
  on public.rate_events (actor, action, at);

-- RLS on + no policies = default-deny for every direct client read/write. Only
-- the SECURITY DEFINER check_rate() (running as owner) can touch these rows.
alter table public.rate_events enable row level security;
revoke all on public.rate_events from anon, authenticated;

-- Enforce a per-caller cap of [p_max] actions per [p_window]. Void on success;
-- raises 'PT429' (mnemonic: HTTP 429) when the caller is at or over the cap. The
-- Nth+1 call in a window is rejected BEFORE its event is recorded, so exactly
-- p_max actions succeed per window.
create or replace function public.check_rate(
  p_action text,
  p_max    int,
  p_window interval
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  n   int;
begin
  if uid is null then
    raise exception 'must be signed in' using errcode = '28000';
  end if;

  -- Opportunistic cleanup: drop this caller+action's rows older than the window
  -- so the table stays small for anyone who keeps acting.
  delete from public.rate_events
   where actor = uid and action = p_action and at < now() - p_window;

  select count(*) into n
    from public.rate_events
   where actor = uid and action = p_action and at >= now() - p_window;

  if n >= p_max then
    raise exception 'rate limit exceeded for %', p_action
      using errcode = 'PT429',
            hint = 'Too many requests — please wait a moment and try again.';
  end if;

  insert into public.rate_events (actor, action) values (uid, p_action);
end;
$$;

-- Internal helper only — never a client RPC. Same-owner SECURITY DEFINER callers
-- (below) can still invoke it; direct client calls are denied.
revoke all on function public.check_rate(text, int, interval) from public;

-- Global sweep of stale rows (for callers who never returned to trigger the
-- opportunistic per-caller cleanup). Optional to schedule, e.g. via pg_cron:
--   select cron.schedule('rate-events-gc','7 4 * * *',
--                        $$select public.cleanup_rate_events()$$);
-- The table is tiny regardless, so this is housekeeping, not correctness.
create or replace function public.cleanup_rate_events()
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.rate_events where at < now() - interval '1 day';
$$;
revoke all on function public.cleanup_rate_events() from public;


-- ─────────────────────────────────────────────────────────────────────────────
-- 1) find_user_by_username — throttle profile-directory harvesting.
--    Converted from language sql → plpgsql so it can guard before resolving.
--    Signature + return type unchanged, so CREATE OR REPLACE is safe. 30/min is
--    far above any real "add a friend by handle" usage; it just caps bulk lookups.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.find_user_by_username(name text)
returns table (id uuid, username text, display_name text, avatar_color text)
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.check_rate('find_user', 30, interval '1 minute');
  return query
    select p.id, p.username, p.display_name, p.avatar_color
    from public.profiles p
    where p.username = lower(name)
    limit 1;
end;
$$;

revoke all on function public.find_user_by_username(text) from public;
grant execute on function public.find_user_by_username(text) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────────
-- 2) join_group_by_code — throttle invite-code brute force. 15/hour makes the
--    6-char (~8.9e8) space astronomically slow to brute, while a real user
--    (who joins rarely, maybe retries a typo) never hits it. Body is otherwise
--    identical to 0006.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.join_group_by_code(code text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  gid uuid;
begin
  if uid is null then
    raise exception 'must be signed in to join a group';
  end if;

  perform public.check_rate('join_group', 15, interval '1 hour');

  select id into gid
  from public.groups
  where invite_code = upper(btrim(code));

  if gid is null then
    raise exception 'no group with that code';
  end if;

  insert into public.group_members (group_id, user_id, role)
    values (gid, uid, 'member')
    on conflict (group_id, user_id) do nothing;

  return gid;
end;
$$;

revoke all on function public.join_group_by_code(text) from public;
grant execute on function public.join_group_by_code(text) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────────
-- 3) friend-request spam — friendships are created by direct client INSERT under
--    RLS (no RPC), so the guard is a BEFORE INSERT trigger. SECURITY DEFINER so
--    it may call the internal check_rate. 20 outgoing requests/hour is well above
--    real use, well below spam. auth.uid() is the requester (RLS guarantees
--    requester = auth.uid() on insert), so the limit is per-requester.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.friendships_rate_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.check_rate('friend_request', 20, interval '1 hour');
  return new;
end;
$$;

drop trigger if exists friendships_rate_limit_trg on public.friendships;
create trigger friendships_rate_limit_trg
  before insert on public.friendships
  for each row execute function public.friendships_rate_limit();
