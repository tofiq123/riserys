-- Rise · Phase 17 · crew wake-feed + emoji reactions (tables + RLS)
--
-- Apply AFTER 0001-0008 (Supabase SQL editor or `supabase db push`).
--
-- Design notes (SECURITY IS THE #1 PRIORITY — this is a NEW read surface for a
-- user's wake activity + their crew's reactions; read before touching a policy):
--   * A `wake_feed` row is one celebratory "I woke up" item the app posts for the
--     signed-in user after a finalized on-time wake. It is append-only: there is
--     no UPDATE policy, so a row's contents are immutable once written (a wake
--     can't be retro-edited). The author may DELETE their own item.
--   * `feed_reactions` is one row per (feed item, reactor, emoji) — a crew member
--     cheering a wake with 🔥/👏/💪/☀️. `unique(feed_id, reactor_id, emoji)`
--     makes a reaction idempotent (double-tap is a no-op, not a duplicate).
--   * Visibility is friendship-scoped, exactly like statuses/stats (0003/0004):
--       - wake_feed SELECT: your own items OR items authored by an ACCEPTED
--         friend, via the SECURITY DEFINER `public.are_friends` helper (defined
--         in 0007). No policy reads its own table, so there is no recursion.
--       - feed_reactions INSERT/SELECT are gated by a SECURITY DEFINER helper
--         `can_see_feed(feed_id, uid)` that re-derives "is this feed item mine or
--         a friend's". A reaction can therefore only be attached to — and read
--         on — a feed item the caller is actually allowed to see. `can_see_feed`
--         reads `wake_feed` (bypassing RLS as it runs as owner), and the
--         `wake_feed` policies never read `feed_reactions`, so no cycle exists.
--   * Every helper is `security definer set search_path = ''` with schema-
--     qualified tables; `revoke all ... from public; grant execute ... to
--     authenticated` (mirrors 0006/0007).
--   * Account delete cascades: wake_feed.user_id and feed_reactions.reactor_id
--     reference auth.users ON DELETE CASCADE, and feed_reactions.feed_id
--     references wake_feed ON DELETE CASCADE — so deleting a user removes their
--     feed items, the reactions on those items, and their reactions elsewhere.
--
-- Build-verified only: no live backend in CI. A two-account post/react smoke test
-- lives in the Phase 17 setup guide.


-- ─────────────────────────────────────────────────────────────────────────────
-- Tables
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.wake_feed (
  id         uuid        primary key default gen_random_uuid(),
  user_id    uuid        not null references auth.users (id) on delete cascade,
  woke_at    timestamptz not null,
  on_time    boolean     not null default false,
  streak     int         not null default 0,
  created_at timestamptz not null default now(),
  -- One feed item per wake: the client posts a wake keyed by its exact dismissal
  -- instant, so a re-post of the same wake (e.g. on a later cold start) collides
  -- here and is ignored rather than duplicated. This is the server-side backstop
  -- to the client's in-memory dedupe.
  constraint wake_feed_one_per_wake unique (user_id, woke_at)
);

-- "My + friends' recent activity", newest first (RLS filters which rows return).
create index if not exists wake_feed_user_created_idx
  on public.wake_feed (user_id, created_at desc);

create table if not exists public.feed_reactions (
  id         uuid        primary key default gen_random_uuid(),
  feed_id    uuid        not null references public.wake_feed (id) on delete cascade,
  reactor_id uuid        not null references auth.users (id)      on delete cascade,
  emoji      text        not null,
  created_at timestamptz not null default now(),
  constraint feed_reactions_emoji_len check (char_length(emoji) between 1 and 16),
  constraint feed_reactions_unique unique (feed_id, reactor_id, emoji)
);
-- The unique constraint's index (feed_id, reactor_id, emoji) already covers the
-- per-item reaction lookup (leading column feed_id), so no extra index is needed.


-- ─────────────────────────────────────────────────────────────────────────────
-- Visibility helper. True iff [feed_id] is a feed item the [uid] user may see:
-- their own, or one authored by an accepted friend. SECURITY DEFINER so the
-- feed_reactions policies can consult wake_feed without depending on the caller's
-- RLS there (and without recursion — wake_feed policies never read
-- feed_reactions). auth.uid() is never used inside; callers pass the subject
-- explicitly. Empty search_path; every table schema-qualified. Reuses the 0007
-- `public.are_friends(a, b)` accepted-friendship helper.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.can_see_feed(feed_id uuid, uid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.wake_feed f
    where f.id = feed_id
      and (f.user_id = uid or public.are_friends(uid, f.user_id))
  );
$$;

revoke all on function public.can_see_feed(uuid, uuid) from public;
grant execute on function public.can_see_feed(uuid, uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────────
-- RLS · wake_feed
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.wake_feed enable row level security;

-- INSERT: only your own item. There is no SECURITY DEFINER insert path, so a
-- feed item can never be planted under another user's name.
drop policy if exists wake_feed_insert_own on public.wake_feed;
create policy wake_feed_insert_own on public.wake_feed for insert
  with check (user_id = auth.uid());

-- SELECT: your own items, or an accepted friend's. No recursion: reads
-- friendships via the SECURITY DEFINER are_friends, never wake_feed itself.
drop policy if exists wake_feed_select_own_or_friend on public.wake_feed;
create policy wake_feed_select_own_or_friend on public.wake_feed for select
  using (user_id = auth.uid() or public.are_friends(auth.uid(), user_id));

-- DELETE: only your own item (retract a post). No one can delete another's item.
drop policy if exists wake_feed_delete_own on public.wake_feed;
create policy wake_feed_delete_own on public.wake_feed for delete
  using (user_id = auth.uid());

-- UPDATE: intentionally NO policy → RLS default-denies every update. Feed items
-- are append-only; on_time / streak / woke_at are frozen once posted.


-- ─────────────────────────────────────────────────────────────────────────────
-- RLS · feed_reactions
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.feed_reactions enable row level security;

-- INSERT: only as yourself, and only onto a feed item you can actually see
-- (your own or a friend's). A stranger cannot react to — nor thereby probe the
-- existence of — a feed item outside their crew.
drop policy if exists feed_reactions_insert_own on public.feed_reactions;
create policy feed_reactions_insert_own on public.feed_reactions for insert
  with check (
    reactor_id = auth.uid()
    and public.can_see_feed(feed_id, auth.uid())
  );

-- SELECT: reactions on any feed item you can see (so a reaction row shows every
-- crew member's cheer, friends of the author or not — but only on items visible
-- to you).
drop policy if exists feed_reactions_select_visible on public.feed_reactions;
create policy feed_reactions_select_visible on public.feed_reactions for select
  using (public.can_see_feed(feed_id, auth.uid()));

-- DELETE: only your own reaction (toggle off). You can always remove a reaction
-- you made, even if the item later leaves your view.
drop policy if exists feed_reactions_delete_own on public.feed_reactions;
create policy feed_reactions_delete_own on public.feed_reactions for delete
  using (reactor_id = auth.uid());

-- UPDATE: intentionally NO policy → RLS default-denies. A reaction is created or
-- deleted, never mutated (changing the emoji = delete + insert).
