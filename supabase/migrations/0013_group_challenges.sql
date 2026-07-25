-- Rise · Group challenges · streak race
--
-- Apply AFTER 0001–0012 (Supabase SQL editor or `supabase db push`). Idempotent.
--
-- A group can run one "streak race" at a time: this table is just a marker for
-- WHEN the race started. Standings are derived client-side from members'
-- already-synced wake streaks (stats, 0004/0005) + this start time — there are
-- no per-member challenge rows to keep in sync.
--
-- Security mirrors 0006 groups: every membership/ownership test goes through the
-- SECURITY DEFINER helpers is_group_member / is_group_owner (which bypass RLS),
-- so referencing group membership here never recurses. Build-verified only: no
-- live backend in CI (the 2-account smoke test lives in the setup guide).

create table if not exists public.group_challenges (
  id         uuid        primary key default gen_random_uuid(),
  group_id   uuid        not null references public.groups (id) on delete cascade,
  kind       text        not null default 'streak_race'
                         check (kind in ('streak_race')),
  started_at timestamptz not null default now(),
  created_by uuid        not null references auth.users (id) on delete cascade,
  ended_at   timestamptz -- null = active
);

create index if not exists group_challenges_group_idx
  on public.group_challenges (group_id);

-- At most ONE active race per group. A partial unique index makes "start a
-- second race while one is running" fail atomically (unique_violation, 23505),
-- while any number of past/ended races are allowed.
create unique index if not exists group_challenges_one_active
  on public.group_challenges (group_id) where ended_at is null;

alter table public.group_challenges enable row level security;

-- SELECT: any member of the group can see its races.
drop policy if exists group_challenges_select_member on public.group_challenges;
create policy group_challenges_select_member on public.group_challenges for select
  using (public.is_group_member(group_id, auth.uid()));

-- INSERT: the group OWNER only, as themselves.
drop policy if exists group_challenges_insert_owner on public.group_challenges;
create policy group_challenges_insert_owner on public.group_challenges for insert
  with check (
    created_by = auth.uid()
    and public.is_group_owner(group_id, auth.uid())
  );

-- UPDATE: owner only (to end the race). The guard trigger below freezes every
-- column except ended_at, so this can only stop a race, never rewrite one.
drop policy if exists group_challenges_update_owner on public.group_challenges;
create policy group_challenges_update_owner on public.group_challenges for update
  using (public.is_group_owner(group_id, auth.uid()))
  with check (public.is_group_owner(group_id, auth.uid()));

-- DELETE: owner only (plus the FK cascade when the group is disbanded).
drop policy if exists group_challenges_delete_owner on public.group_challenges;
create policy group_challenges_delete_owner on public.group_challenges for delete
  using (public.is_group_owner(group_id, auth.uid()));

-- Immutability guard: only ended_at may change (mirrors the 0006 guards). This
-- is the escalation backstop — the owner-only UPDATE policy can then only ever
-- set the end time, never move a race to another group or rewrite its start.
create or replace function public.group_challenges_guard_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.id <> old.id
     or new.group_id <> old.group_id
     or new.kind <> old.kind
     or new.started_at <> old.started_at
     or new.created_by <> old.created_by then
    raise exception 'only ended_at may be changed on a challenge';
  end if;
  return new;
end;
$$;

drop trigger if exists group_challenges_guard_update_trg on public.group_challenges;
create trigger group_challenges_guard_update_trg
  before update on public.group_challenges
  for each row execute function public.group_challenges_guard_update();
