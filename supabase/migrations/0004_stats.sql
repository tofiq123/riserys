-- Rise · Phase 5e · stats + RLS
--
-- Apply AFTER 0001_profiles.sql, 0002_friendships.sql, 0003_statuses.sql
-- (Supabase SQL editor or `supabase db push`).
--
-- Each user has one aggregate-stats row, upserted by the app from local wake
-- data. RLS mirrors `statuses`: own row read/write; read a crew member's stats
-- only for an ACCEPTED friendship. The leaderboard fetches on open (no Realtime).

create table if not exists public.stats (
  user_id        uuid        primary key references auth.users (id) on delete cascade,
  current_streak int         not null default 0,
  best_streak    int         not null default 0,
  total_wakes    int         not null default 0,
  on_time        int         not null default 0,
  updated_at     timestamptz not null default now()
);

alter table public.stats enable row level security;

-- Own row: full read/write.
drop policy if exists stats_own on public.stats;
create policy stats_own on public.stats for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Read a crew member's stats only when there is an ACCEPTED friendship between
-- you and them. No recursion: this reads `friendships`, which never reads
-- `stats`.
drop policy if exists stats_select_crew on public.stats;
create policy stats_select_crew on public.stats for select
  using (
    exists (
      select 1 from public.friendships f
      where f.status = 'accepted'
        and (
          (f.requester = auth.uid() and f.addressee = public.stats.user_id)
          or (f.addressee = auth.uid() and f.requester = public.stats.user_id)
        )
    )
  );
