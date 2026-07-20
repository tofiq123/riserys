-- Rise · Phase 16 · voice clips (table + RLS) + private Storage bucket + Storage RLS
--
-- Apply AFTER 0001-0006 (Supabase SQL editor or `supabase db push`).
--
-- Design notes (SECURITY IS THE #1 PRIORITY — Storage is a NEW attack surface;
-- read before touching a policy):
--   * A voice clip is a short audio file `owner` records and sends to `target`.
--     The AUDIO BYTES live in a PRIVATE Storage bucket `voice-clips` under the
--     path `<owner_id>/<random>.m4a`; the `voice_clips` ROW is the metadata +
--     the sender→recipient mapping that authorizes reads of that object.
--   * Two RLS surfaces, kept consistent:
--       - public.voice_clips (metadata): INSERT only your own row AND only to an
--         accepted friend; SELECT to sender OR recipient; DELETE by sender OR
--         recipient; UPDATE only by the recipient and ONLY to stamp played_at
--         (a BEFORE-UPDATE guard freezes every other column, mirroring the 0002
--         friendships / 0006 groups immutability triggers).
--       - storage.objects (bytes): a user may write/replace/delete objects ONLY
--         under their own `<uid>/` prefix; a user may READ an object iff they are
--         its owner (path prefix) OR they are the `target_id` of a voice_clips
--         row that points at that exact path (via a SECURITY DEFINER helper).
--         Net effect: a clip's bytes are reachable by exactly its sender + its
--         one recipient, and by no one else — even though the bucket is shared.
--   * Friendship is checked through a SECURITY DEFINER helper `are_friends`
--     (empty search_path, schema-qualified) so the INSERT policy never depends on
--     the caller's RLS view of `friendships`. No policy reads its own table, so
--     there is no recursion.
--   * `set search_path = ''` on every function; all tables schema-qualified.
--
-- Build-verified only: no live backend in CI. The bucket + a two-account
-- send/receive smoke test are in the Phase 16 setup guide. If the bucket-insert
-- at the bottom of this file fails for lack of privilege in the SQL editor,
-- create a PRIVATE bucket named `voice-clips` in the dashboard by hand — the
-- policies below still apply to it.


-- ─────────────────────────────────────────────────────────────────────────────
-- Friendship helper. True iff `a` and `b` have an ACCEPTED friendship (either
-- direction). SECURITY DEFINER so it bypasses the caller's RLS on `friendships`
-- (the INSERT policy below must be able to assert the pair are friends
-- regardless of which rows the caller can see). Empty search_path.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.are_friends(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.friendships f
    where f.status = 'accepted'
      and (
        (f.requester = a and f.addressee = b) or
        (f.requester = b and f.addressee = a)
      )
  );
$$;

revoke all on function public.are_friends(uuid, uuid) from public;
grant execute on function public.are_friends(uuid, uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────────
-- Table
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.voice_clips (
  id           uuid        primary key default gen_random_uuid(),
  owner_id     uuid        not null references auth.users (id) on delete cascade,
  target_id    uuid        not null references auth.users (id) on delete cascade,
  storage_path text        not null,
  duration_ms  int         not null default 0,
  created_at   timestamptz not null default now(),
  played_at    timestamptz,
  constraint voice_clips_distinct  check (owner_id <> target_id),
  -- 30s cap (matches kMaxVoiceClipDuration) with a small tolerance for the
  -- client's stopwatch rounding; the app clamps to 30000 before insert.
  constraint voice_clips_duration  check (duration_ms >= 0 and duration_ms <= 31000)
);

-- "My inbox": clips addressed to me, newest first.
create index if not exists voice_clips_target_idx
  on public.voice_clips (target_id, created_at desc);
create index if not exists voice_clips_owner_idx
  on public.voice_clips (owner_id);
-- Backs the Storage read-authorization lookup (storage_path → recipient).
create index if not exists voice_clips_path_idx
  on public.voice_clips (storage_path);

alter table public.voice_clips enable row level security;


-- ─────────────────────────────────────────────────────────────────────────────
-- RLS · voice_clips
-- ─────────────────────────────────────────────────────────────────────────────

-- INSERT: only your own clip (owner_id = you), only TO an accepted friend, and
-- never pre-stamped as played. This is the only way a row is created — there is
-- no SECURITY DEFINER insert path, so a clip can never be planted on a stranger.
drop policy if exists voice_clips_insert_own on public.voice_clips;
create policy voice_clips_insert_own on public.voice_clips for insert
  with check (
    owner_id = auth.uid()
    and target_id <> auth.uid()
    and played_at is null
    and public.are_friends(auth.uid(), target_id)
  );

-- SELECT: the two parties only. No one else can read the metadata (nor, via the
-- Storage helper below, the bytes).
drop policy if exists voice_clips_select_involved on public.voice_clips;
create policy voice_clips_select_involved on public.voice_clips for select
  using (auth.uid() = owner_id or auth.uid() = target_id);

-- UPDATE: only the recipient, and (via the guard trigger) only to set played_at.
-- The WITH CHECK cannot see the OLD row, so the trigger is what actually freezes
-- owner_id / target_id / storage_path / duration_ms / created_at and makes
-- played_at write-once.
drop policy if exists voice_clips_update_target on public.voice_clips;
create policy voice_clips_update_target on public.voice_clips for update
  using (auth.uid() = target_id)
  with check (auth.uid() = target_id);

-- DELETE: either party may delete their copy (sender unsends; recipient clears
-- their inbox). Deleting the row also strips read-access to the bytes (the
-- Storage helper needs a row), so an orphaned object is unreadable by anyone.
drop policy if exists voice_clips_delete_involved on public.voice_clips;
create policy voice_clips_delete_involved on public.voice_clips for delete
  using (auth.uid() = owner_id or auth.uid() = target_id);


-- Freeze everything but played_at, and make played_at write-once (null → ts).
-- Mirrors the 0002 friendships / 0006 groups guard-trigger pattern. Plain
-- (no SECURITY DEFINER) — it does no cross-table lookup.
create or replace function public.voice_clips_guard_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.id <> old.id
     or new.owner_id <> old.owner_id
     or new.target_id <> old.target_id
     or new.storage_path <> old.storage_path
     or new.duration_ms <> old.duration_ms
     or new.created_at <> old.created_at then
    raise exception 'only played_at may be updated on a voice clip';
  end if;
  if old.played_at is not null and new.played_at is distinct from old.played_at then
    raise exception 'played_at is write-once';
  end if;
  return new;
end;
$$;

drop trigger if exists voice_clips_guard_update_trg on public.voice_clips;
create trigger voice_clips_guard_update_trg
  before update on public.voice_clips
  for each row execute function public.voice_clips_guard_update();


-- ─────────────────────────────────────────────────────────────────────────────
-- Storage read-authorization helper. True iff the caller is the `target_id` of
-- a voice_clips row whose storage_path is exactly [object_name]. SECURITY
-- DEFINER so the storage.objects SELECT policy can consult public.voice_clips
-- without depending on the caller's RLS there and without any recursion.
-- auth.uid() still resolves to the CALLER (it reads the request JWT, which
-- SECURITY DEFINER does not change). Empty search_path; storage/auth qualified.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.is_voice_clip_recipient(object_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.voice_clips v
    where v.storage_path = object_name
      and v.target_id = auth.uid()
  );
$$;

revoke all on function public.is_voice_clip_recipient(text) from public;
grant execute on function public.is_voice_clip_recipient(text) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────────
-- Storage bucket (PRIVATE). Idempotent. If your SQL-editor role lacks privilege
-- to write storage.buckets, this line errors — in that case create a PRIVATE
-- bucket named `voice-clips` in the dashboard (Storage → New bucket, "Public"
-- OFF) and re-run from the policies below. file_size_limit + allowed_mime_types
-- are defense-in-depth (a 30s mono AAC clip is well under 1 MB).
-- ─────────────────────────────────────────────────────────────────────────────
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'voice-clips', 'voice-clips', false, 2097152,
  array['audio/mp4', 'audio/aac', 'audio/x-m4a', 'audio/m4a', 'audio/mpeg']
)
on conflict (id) do nothing;


-- ─────────────────────────────────────────────────────────────────────────────
-- RLS · storage.objects (scoped to the voice-clips bucket). RLS is already
-- enabled on storage.objects by Supabase. `(storage.foldername(name))[1]` is the
-- first path segment — our `<owner_id>/` prefix.
-- ─────────────────────────────────────────────────────────────────────────────

-- WRITE own prefix only: a user may create objects solely under `<their uid>/`.
drop policy if exists voice_clips_objects_insert_own on storage.objects;
create policy voice_clips_objects_insert_own on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'voice-clips'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- REPLACE own prefix only (covers upsert). Same prefix on the old and new name.
drop policy if exists voice_clips_objects_update_own on storage.objects;
create policy voice_clips_objects_update_own on storage.objects for update
  to authenticated
  using (
    bucket_id = 'voice-clips'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'voice-clips'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- DELETE own prefix only: only the owner can remove the bytes. (A recipient can
-- delete the metadata row, which is enough to drop their inbox entry + revoke
-- read access; the object is then an unreadable orphan.)
drop policy if exists voice_clips_objects_delete_own on storage.objects;
create policy voice_clips_objects_delete_own on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'voice-clips'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- READ: the owner (path prefix is their uid) OR the designated recipient of a
-- voice_clips row pointing at this exact object. This is what gates
-- createSignedUrl / download for the recipient — no third party can read.
drop policy if exists voice_clips_objects_select_involved on storage.objects;
create policy voice_clips_objects_select_involved on storage.objects for select
  to authenticated
  using (
    bucket_id = 'voice-clips'
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or public.is_voice_clip_recipient(name)
    )
  );
