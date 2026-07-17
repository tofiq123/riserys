-- Rise · Phase 5a · profiles + RLS
--
-- The account layer's only table for 5a. A profile row is created when a user
-- claims a username after their first Google sign-in. Apply this in the
-- Supabase SQL editor, or with `supabase db push`.
--
-- Design notes:
--   * `id` references `auth.users(id)` with ON DELETE CASCADE, so deleting the
--     auth user (see the delete-account edge function) removes the profile too.
--   * Usernames are stored lowercased and constrained to 3–20 chars of
--     [a-z0-9_]; the `unique` constraint is the real guard against duplicates
--     (the app's availability check is a best-effort UX pre-check only).
--   * RLS is own-row-only for 5a. Broader read (needed to see friends) arrives
--     in 5b together with the friendships table, so we do not over-grant now.

create table if not exists public.profiles (
  id           uuid        primary key references auth.users (id) on delete cascade,
  username     text        not null,
  display_name text        not null default '',
  avatar_color text        not null default '#7C9CF4',
  tz           text,
  created_at   timestamptz not null default now(),
  constraint profiles_username_unique unique (username),
  constraint profiles_username_format check (username ~ '^[a-z0-9_]{3,20}$')
);

-- (The `profiles_username_unique` constraint already creates a unique index on
-- username, which serves equality lookups for the availability RPC and future
-- friend search — no separate index is needed.)

alter table public.profiles enable row level security;

-- A user may read / insert / update ONLY their own row.
drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own
  on public.profiles for select
  using (auth.uid() = id);

drop policy if exists profiles_insert_own on public.profiles;
create policy profiles_insert_own
  on public.profiles for insert
  with check (auth.uid() = id);

drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own
  on public.profiles for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- Availability pre-check.
--
-- Because RLS keeps other users' rows private in 5a, a plain client-side
-- `select ... where username = ?` would never see a taken name and would always
-- report "available". This SECURITY DEFINER function checks existence
-- server-side and returns ONLY a boolean, so it powers a real availability
-- check without exposing any other user's profile data. The `unique` constraint
-- remains the actual guard against a race between the check and the insert.
create or replace function public.username_available(name text)
returns boolean
language sql
security definer
-- Empty search_path so nothing resolves via an ambient/hijackable path; every
-- object below is schema-qualified (`public.profiles`), and `lower()` resolves
-- from the always-implicit `pg_catalog`.
set search_path = ''
as $$
  select not exists (
    select 1 from public.profiles where username = lower(name)
  );
$$;

revoke all on function public.username_available(text) from public;
grant execute on function public.username_available(text) to authenticated;
