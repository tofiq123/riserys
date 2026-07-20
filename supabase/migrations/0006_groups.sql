-- Rise · Phase 15 · groups + membership + RLS + join-by-code
--
-- Apply AFTER 0001-0005 (Supabase SQL editor or `supabase db push`).
--
-- Design notes (SECURITY IS THE #1 PRIORITY — read before touching a policy):
--   * A `group` is created by an owner. Membership lives in `group_members`
--     (one row per (group, user)). `groups.owner_id` is the single source of
--     truth for ownership; `group_members.role` is a display convenience.
--   * NO group_members policy may read group_members directly (Postgres raises
--     "infinite recursion detected in policy"). Every membership/ownership test
--     inside a policy goes through a SECURITY DEFINER helper
--     (`is_group_member` / `is_group_owner` / `shares_group`) that runs as the
--     function owner and therefore BYPASSES RLS — breaking the recursion.
--   * Joining is capability-based: `groups`/`group_members` SELECT is
--     members-only, so a non-member can neither enumerate nor read a group. The
--     invite_code is the capability; `join_group_by_code` (SECURITY DEFINER) is
--     the app's join path. group ids are v4 uuids and are never surfaced to
--     non-members, so the code is the only practical way in.
--   * All identity columns are immutable via BEFORE-triggers (mirroring the
--     0002 friendships guard): owner_id/id/invite_code on `groups`, and
--     group_id/user_id/role on `group_members`. This blocks every privilege
--     escalation (e.g. a member rewriting their own role to 'owner').
--   * The owner cannot "leave" (that would orphan an owned group); they disband
--     by deleting the group (cascade removes members). A BEFORE DELETE trigger
--     enforces this while still allowing the group-delete cascade to run.
--   * Group leaderboards need to read fellow members' profiles + stats even when
--     they are not friends, so this migration ADDS (does not replace) permissive
--     SELECT policies to `profiles` and `stats` for co-group-members.
--
-- Build-verified only: no live backend in CI. The two-account join/leaderboard
-- smoke test lives in the Phase 15 setup guide.


-- ─────────────────────────────────────────────────────────────────────────────
-- Invite-code generator. 6 chars from an unambiguous alphabet (no 0/O/1/I/L).
-- VOLATILE so it re-rolls per row / per retry. Empty search_path; random(),
-- floor(), substr(), string_agg(), generate_series() all resolve from the
-- always-implicit pg_catalog. Not exposed as an RPC (revoked from public); it is
-- only ever called by the column default and create_group (both run as owner).
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.gen_invite_code()
returns text
language sql
volatile
set search_path = ''
as $$
  select string_agg(
           substr('ABCDEFGHJKMNPQRSTUVWXYZ23456789',
                  1 + floor(random() * 31)::int, 1),
           '')
  from generate_series(1, 6);
$$;

revoke all on function public.gen_invite_code() from public;


-- ─────────────────────────────────────────────────────────────────────────────
-- Tables
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.groups (
  id          uuid        primary key default gen_random_uuid(),
  name        text        not null,
  owner_id    uuid        not null references auth.users (id) on delete cascade,
  invite_code text        not null unique default public.gen_invite_code(),
  created_at  timestamptz not null default now(),
  constraint groups_name_len    check (char_length(name) between 1 and 40),
  constraint groups_code_format check (invite_code ~ '^[A-Z0-9]{4,16}$')
);

create index if not exists groups_owner_idx on public.groups (owner_id);

create table if not exists public.group_members (
  group_id  uuid        not null references public.groups (id) on delete cascade,
  user_id   uuid        not null references auth.users (id)   on delete cascade,
  role      text        not null default 'member' check (role in ('owner', 'member')),
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

-- The PK indexes (group_id, user_id); this covers "my groups" (filter user_id).
create index if not exists group_members_user_idx on public.group_members (user_id);


-- ─────────────────────────────────────────────────────────────────────────────
-- SECURITY DEFINER helpers used inside policies. Each runs as the function owner
-- and BYPASSES RLS, so referencing group_members from a group_members policy
-- does NOT recurse. Empty search_path; every table is schema-qualified.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.is_group_member(gid uuid, uid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.group_members m
    where m.group_id = gid and m.user_id = uid
  );
$$;

create or replace function public.is_group_owner(gid uuid, uid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.groups g
    where g.id = gid and g.owner_id = uid
  );
$$;

-- True when users `a` and `b` share at least one group. Used to widen the
-- profiles/stats read policies so a group leaderboard can show every member's
-- handle + streak, friends or not.
create or replace function public.shares_group(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.group_members m1
    join public.group_members m2 on m1.group_id = m2.group_id
    where m1.user_id = a and m2.user_id = b
  );
$$;

revoke all on function public.is_group_member(uuid, uuid) from public;
revoke all on function public.is_group_owner(uuid, uuid)  from public;
revoke all on function public.shares_group(uuid, uuid)    from public;
grant execute on function public.is_group_member(uuid, uuid) to authenticated;
grant execute on function public.is_group_owner(uuid, uuid)  to authenticated;
grant execute on function public.shares_group(uuid, uuid)    to authenticated;


-- ─────────────────────────────────────────────────────────────────────────────
-- RLS · groups
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.groups enable row level security;

-- SELECT: members only. A non-member cannot read (or enumerate) any group row —
-- not even by guessing an id. (No recursion: this policy reads group_members via
-- the SECURITY DEFINER helper, never `groups`.)
drop policy if exists groups_select_member on public.groups;
create policy groups_select_member on public.groups for select
  using (public.is_group_member(id, auth.uid()));

-- INSERT: any signed-in user may create a group, but only as its own owner.
-- (The app creates groups via create_group, which also inserts the owner's
-- member row atomically; a bare client insert would leave the creator unable to
-- even read the row back, since they are not yet a member.)
drop policy if exists groups_insert_owner on public.groups;
create policy groups_insert_owner on public.groups for insert
  with check (owner_id = auth.uid());

-- UPDATE: owner only (e.g. rename). The guard trigger below keeps id/owner_id/
-- invite_code immutable, so this can only change `name`.
drop policy if exists groups_update_owner on public.groups;
create policy groups_update_owner on public.groups for update
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

-- DELETE: owner only (disband). Cascades to group_members.
drop policy if exists groups_delete_owner on public.groups;
create policy groups_delete_owner on public.groups for delete
  using (owner_id = auth.uid());


-- ─────────────────────────────────────────────────────────────────────────────
-- RLS · group_members
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.group_members enable row level security;

-- SELECT: fellow members of the same group (so a member can list the roster).
-- Via the SECURITY DEFINER helper → no recursion.
drop policy if exists group_members_select_member on public.group_members;
create policy group_members_select_member on public.group_members for select
  using (public.is_group_member(group_id, auth.uid()));

-- INSERT: intentionally NO policy → RLS default-denies every direct client
-- insert into group_members. Both legitimate join paths are SECURITY DEFINER
-- functions that bypass RLS: create_group() writes the owner row, and
-- join_group_by_code() writes the member row after validating the invite code.
-- This makes the invite_code the SOLE capability to join — a user can never
-- self-join a group merely by knowing its uuid, closing a latent hole should a
-- group id ever leak to a non-member. (Drop any prior policy for idempotent
-- re-runs.)
drop policy if exists group_members_insert_self on public.group_members;

-- UPDATE: owner only. Combined with the immutable-columns guard below (which
-- freezes role too), no update can escalate anyone — this policy plus the guard
-- means membership rows are effectively frozen once created. Role/ownership
-- transfer is intentionally out of scope for this phase.
drop policy if exists group_members_update_owner on public.group_members;
create policy group_members_update_owner on public.group_members for update
  using (public.is_group_owner(group_id, auth.uid()))
  with check (public.is_group_owner(group_id, auth.uid()));

-- DELETE: a user may remove themselves (leave); the owner may remove any member
-- (kick). The BEFORE DELETE guard below blocks the owner from leaving.
drop policy if exists group_members_delete_self_or_owner on public.group_members;
create policy group_members_delete_self_or_owner on public.group_members for delete
  using (user_id = auth.uid() or public.is_group_owner(group_id, auth.uid()));


-- ─────────────────────────────────────────────────────────────────────────────
-- Guard triggers (mirror the 0002 friendships immutability pattern)
-- ─────────────────────────────────────────────────────────────────────────────

-- groups: only `name` may change. id / owner_id / invite_code / created_at are
-- immutable, so the owner-only UPDATE policy can never be leveraged to reassign
-- ownership or hijack a group's identity.
create or replace function public.groups_guard_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.id <> old.id
     or new.owner_id <> old.owner_id
     or new.invite_code <> old.invite_code
     or new.created_at <> old.created_at then
    raise exception 'only the group name may be changed';
  end if;
  return new;
end;
$$;

drop trigger if exists groups_guard_update_trg on public.groups;
create trigger groups_guard_update_trg
  before update on public.groups
  for each row execute function public.groups_guard_update();

-- group_members: the identity + role are immutable. This is the escalation
-- backstop — even the owner (the only role allowed to UPDATE) cannot flip a
-- member row to 'owner' or move it to another user.
create or replace function public.group_members_guard_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.group_id <> old.group_id
     or new.user_id <> old.user_id
     or new.role <> old.role then
    raise exception 'group membership rows are immutable';
  end if;
  return new;
end;
$$;

drop trigger if exists group_members_guard_update_trg on public.group_members;
create trigger group_members_guard_update_trg
  before update on public.group_members
  for each row execute function public.group_members_guard_update();

-- group_members: block the owner from leaving their own group (that would leave
-- an owned-but-ownerless group). They must delete the group instead.
--
-- The `exists` check is what makes a group-delete CASCADE still work: RI cascade
-- removes child rows AFTER the parent groups row is already gone, so by the time
-- this trigger runs during a cascade the parent no longer exists → no raise. A
-- direct owner self-leave still finds the parent present → raise. SECURITY
-- DEFINER so the ownership lookup is reliable regardless of the caller's RLS.
create or replace function public.group_members_guard_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1 from public.groups g
    where g.id = old.group_id and g.owner_id = old.user_id
  ) then
    raise exception 'the owner cannot leave their own group; delete the group instead';
  end if;
  return old;
end;
$$;

drop trigger if exists group_members_guard_delete_trg on public.group_members;
create trigger group_members_guard_delete_trg
  before delete on public.group_members
  for each row execute function public.group_members_guard_delete();


-- ─────────────────────────────────────────────────────────────────────────────
-- Widen profiles + stats reads to co-group-members (ADDITIVE — permissive
-- policies OR together, so these do not weaken the existing own/friend rules).
-- No recursion: both read group_members via the SECURITY DEFINER shares_group.
-- ─────────────────────────────────────────────────────────────────────────────
drop policy if exists profiles_select_group on public.profiles;
create policy profiles_select_group on public.profiles for select
  using (public.shares_group(auth.uid(), public.profiles.id));

drop policy if exists stats_select_group on public.stats;
create policy stats_select_group on public.stats for select
  using (public.shares_group(auth.uid(), public.stats.user_id));


-- ─────────────────────────────────────────────────────────────────────────────
-- RPCs (SECURITY DEFINER). These are the app's create/join paths.
-- ─────────────────────────────────────────────────────────────────────────────

-- Create a group AND the owner's member row atomically, returning the new row.
-- Runs as owner so it can insert the 'owner' role row (which the RLS INSERT
-- policy forbids for direct client calls) and read the row back. Retries on the
-- (astronomically rare) invite_code collision — the column default re-rolls a
-- fresh code on each attempt.
create or replace function public.create_group(name text)
returns public.groups
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  g   public.groups;
begin
  if uid is null then
    raise exception 'must be signed in to create a group';
  end if;
  if char_length(btrim(name)) = 0 then
    raise exception 'a group needs a name';
  end if;

  loop
    begin
      insert into public.groups (name, owner_id)
        values (btrim(name), uid)
        returning * into g;
      exit;
    exception when unique_violation then
      -- invite_code collided; the default re-generates on the next attempt.
    end;
  end loop;

  insert into public.group_members (group_id, user_id, role)
    values (g.id, uid, 'owner');

  return g;
end;
$$;

-- Join a group by its invite code: inserts (group, me, 'member') if not already
-- a member, and returns the group id. This is the app's ONLY join path — knowing
-- the code is the capability. Idempotent (re-joining is a no-op).
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

revoke all on function public.create_group(text)       from public;
revoke all on function public.join_group_by_code(text) from public;
grant execute on function public.create_group(text)       to authenticated;
grant execute on function public.join_group_by_code(text) to authenticated;
