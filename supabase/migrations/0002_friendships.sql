-- Rise · Phase 5b · friendships + RLS + crew profile reads
--
-- Apply AFTER 0001_profiles.sql (Supabase SQL editor or `supabase db push`).
--
-- Design notes:
--   * One row per relationship: `requester` asked `addressee`. `status` is
--     'pending' until the addressee accepts. Deleting the row is
--     decline / cancel / remove.
--   * `unique(requester, addressee)` blocks a same-direction resend; the
--     `friendships_block_reverse` trigger blocks the reverse direction so there
--     is at most ONE relationship per pair.
--   * RLS: see rows you're in; insert only as the requester (pending); only the
--     addressee can accept; either party can delete.
--   * The `profiles` read policy is broadened so crew members can see each
--     other's public profile; `find_user_by_username` lets you resolve a handle
--     to send a request BEFORE any friendship exists.

create table if not exists public.friendships (
  id         uuid        primary key default gen_random_uuid(),
  requester  uuid        not null references auth.users (id) on delete cascade,
  addressee  uuid        not null references auth.users (id) on delete cascade,
  status     text        not null default 'pending' check (status in ('pending', 'accepted')),
  created_at timestamptz not null default now(),
  constraint friendships_distinct check (requester <> addressee),
  constraint friendships_unique unique (requester, addressee)
);

create index if not exists friendships_requester_idx on public.friendships (requester);
create index if not exists friendships_addressee_idx on public.friendships (addressee);

alter table public.friendships enable row level security;

-- See rows you are part of.
drop policy if exists friendships_select_involved on public.friendships;
create policy friendships_select_involved on public.friendships for select
  using (auth.uid() = requester or auth.uid() = addressee);

-- Send a request only as the requester, and only as 'pending'.
drop policy if exists friendships_insert_own on public.friendships;
create policy friendships_insert_own on public.friendships for insert
  with check (auth.uid() = requester and status = 'pending');

-- Only the addressee can accept (flip pending -> accepted).
drop policy if exists friendships_update_addressee on public.friendships;
create policy friendships_update_addressee on public.friendships for update
  using (auth.uid() = addressee)
  with check (auth.uid() = addressee);

-- Either party can delete (decline / cancel / remove).
drop policy if exists friendships_delete_involved on public.friendships;
create policy friendships_delete_involved on public.friendships for delete
  using (auth.uid() = requester or auth.uid() = addressee);

-- Reject a reverse-direction duplicate. `unique(requester, addressee)` is an
-- ORDERED pair, so it would not stop (B, A) when (A, B) already exists. This
-- trigger enforces one relationship per pair regardless of direction, and
-- raises SQLSTATE 23505 so the app maps it to the same "already have a request"
-- message as the unique violation. SECURITY DEFINER so the existence check sees
-- the reverse row even if RLS would hide it from the inserting user.
create or replace function public.friendships_block_reverse()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1 from public.friendships f
    where f.requester = new.addressee and f.addressee = new.requester
  ) then
    raise exception 'a friendship already exists between these users'
      using errcode = '23505';
  end if;
  return new;
end;
$$;

drop trigger if exists friendships_block_reverse_trg on public.friendships;
create trigger friendships_block_reverse_trg
  before insert on public.friendships
  for each row execute function public.friendships_block_reverse();

-- Broaden profile reads: a profile is visible to its owner OR to anyone with a
-- friendship (pending or accepted) with them, so crew lists can show handles /
-- names / avatars. Replaces the own-row-only policy from 0001. No recursion:
-- this subquery reads `friendships`, which never reads `profiles`.
drop policy if exists profiles_select_own on public.profiles;
drop policy if exists profiles_select_own_or_crew on public.profiles;
create policy profiles_select_own_or_crew on public.profiles for select
  using (
    auth.uid() = id
    or exists (
      select 1 from public.friendships f
      where (f.requester = auth.uid() and f.addressee = public.profiles.id)
         or (f.addressee = auth.uid() and f.requester = public.profiles.id)
    )
  );

-- Resolve a username to a minimal public profile so a signed-in user can send a
-- request BEFORE any friendship (and thus profile-read policy) applies.
-- SECURITY DEFINER + empty search_path; returns only public-safe columns; not
-- exposed to anon.
create or replace function public.find_user_by_username(name text)
returns table (id uuid, username text, display_name text, avatar_color text)
language sql
security definer
set search_path = ''
as $$
  select p.id, p.username, p.display_name, p.avatar_color
  from public.profiles p
  where p.username = lower(name)
  limit 1;
$$;

revoke all on function public.find_user_by_username(text) from public;
grant execute on function public.find_user_by_username(text) to authenticated;
