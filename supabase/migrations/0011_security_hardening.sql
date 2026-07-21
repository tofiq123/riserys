-- Rise · defense-in-depth hardening (apply AFTER 0001–0010)
--
-- All three items below are MINOR / belt-and-braces — a security audit found
-- NO exploitable cross-user hole and confirmed every privacy invariant holds.
-- These just close low-probability edges before the user base grows. Each is
-- safe to run on a populated database:
--   * The voice_clips change only recreates an RLS policy (existing rows keep
--     their access; only FUTURE inserts are additionally constrained).
--   * The two CHECK constraints are added NOT VALID, so existing rows are never
--     re-validated — only new writes must satisfy them.
--
-- Idempotent: re-running is safe (drop-policy-if-exists + IF NOT EXISTS guards).

-- 1) voice_clips: a metadata row may only name a storage object under the
--    owner's own folder (`<owner_id>/…`). Without this, a sender could point a
--    row's storage_path at an arbitrary object and grant a friend read to it
--    via the Storage authorization helper. Object names carry 128 bits of
--    randomness so this isn't practically exploitable today, but the prefix
--    rule makes it structurally impossible.
drop policy if exists voice_clips_insert_own on public.voice_clips;
create policy voice_clips_insert_own on public.voice_clips for insert
  with check (
    owner_id = auth.uid()
    and target_id <> auth.uid()
    and played_at is null
    and public.are_friends(auth.uid(), target_id)
    and storage_path like (owner_id::text || '/%')
  );

-- 2) feed_reactions: the emoji is the one client-supplied string shown to other
--    crew members (in-app only — never a push, which stays 100% server-composed).
--    It was length-bounded (1–16) but otherwise free text. Reject anything
--    containing alphanumerics so it can carry an emoji/symbol reaction but not
--    16 characters of arbitrary text. NOT VALID: only new reactions are checked.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'feed_reactions_emoji_no_text'
      and conrelid = 'public.feed_reactions'::regclass
  ) then
    alter table public.feed_reactions
      add constraint feed_reactions_emoji_no_text
      check (emoji !~ '[[:alnum:]]') not valid;
  end if;
end $$;

-- 3) account_backups: cap the self-owned payload at ~1 MB so a misbehaving
--    client can't bloat its own row (self-abuse only; RLS already scopes writes
--    to the caller). NOT VALID: existing rows are left as-is.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'account_backups_payload_size'
      and conrelid = 'public.account_backups'::regclass
  ) then
    alter table public.account_backups
      add constraint account_backups_payload_size
      check (pg_column_size(payload) <= 1048576) not valid;
  end if;
end $$;
