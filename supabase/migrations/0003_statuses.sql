-- Rise · Phase 5c · statuses + RLS + Realtime
--
-- Apply AFTER 0001_profiles.sql and 0002_friendships.sql (Supabase SQL editor
-- or `supabase db push`).
--
-- Each user has one status row (asleep / waking / awake / unknown), upserted by
-- the app from local alarm/wake activity. RLS: own row read/write; read a crew
-- member's status only for an ACCEPTED friendship. The table is added to the
-- Realtime publication so status changes stream to the crew live (RLS still
-- gates what each client receives).

create table if not exists public.statuses (
  user_id    uuid        primary key references auth.users (id) on delete cascade,
  status     text        not null check (status in ('asleep', 'waking', 'awake', 'unknown')),
  updated_at timestamptz not null default now()
);

alter table public.statuses enable row level security;

-- Own row: full read/write (insert/update/select/delete).
drop policy if exists statuses_own on public.statuses;
create policy statuses_own on public.statuses for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Read a crew member's status only when there is an ACCEPTED friendship between
-- you and them (pending requests do NOT reveal status). No recursion: this reads
-- `friendships`, which never reads `statuses`.
drop policy if exists statuses_select_crew on public.statuses;
create policy statuses_select_crew on public.statuses for select
  using (
    exists (
      select 1 from public.friendships f
      where f.status = 'accepted'
        and (
          (f.requester = auth.uid() and f.addressee = public.statuses.user_id)
          or (f.addressee = auth.uid() and f.requester = public.statuses.user_id)
        )
    )
  );

-- REPLICA IDENTITY FULL so DELETE (and UPDATE) Realtime payloads carry the
-- row's user_id, letting the client prune a removed status. Idempotent.
alter table public.statuses replica identity full;

-- Add to the Realtime publication (guarded so re-running the migration is safe).
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'statuses'
  ) then
    alter publication supabase_realtime add table public.statuses;
  end if;
end $$;
