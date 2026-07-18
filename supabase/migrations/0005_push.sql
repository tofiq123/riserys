-- Rise · Phase 5d · push (device tokens + nudge rate-limit log)
--
-- Apply AFTER 0001-0004 (Supabase SQL editor or `supabase db push`).
--
-- device_tokens: the app upserts its own FCM token so the send-nudge edge
-- function (service role) can target the user's devices. nudges: a log the
-- edge function uses to rate-limit. Both are own-row for the client; the edge
-- function reads/writes across users via the service role (bypasses RLS).

create table if not exists public.device_tokens (
  id         uuid        primary key default gen_random_uuid(),
  user_id    uuid        not null references auth.users (id) on delete cascade,
  token      text        not null,
  platform   text        not null default 'android',
  updated_at timestamptz not null default now(),
  constraint device_tokens_unique unique (user_id, token)
);

create index if not exists device_tokens_user_idx on public.device_tokens (user_id);

alter table public.device_tokens enable row level security;

-- Own row only: the client registers/removes its own token. No cross-user read
-- from the client — the edge function reads tokens via the service role.
drop policy if exists device_tokens_own on public.device_tokens;
create policy device_tokens_own on public.device_tokens for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Nudge log, used for rate-limiting (one nudge per from→to per few minutes).
create table if not exists public.nudges (
  id         uuid        primary key default gen_random_uuid(),
  from_user  uuid        not null references auth.users (id) on delete cascade,
  to_user    uuid        not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

create index if not exists nudges_from_created_idx
  on public.nudges (from_user, to_user, created_at);

alter table public.nudges enable row level security;

-- Own rows (as the sender). The edge function inserts via the service role
-- after its own crew + rate-limit checks; this policy just scopes any direct
-- client access (e.g. a future "sent nudges" view) to your own.
drop policy if exists nudges_own on public.nudges;
create policy nudges_own on public.nudges for all
  using (auth.uid() = from_user)
  with check (auth.uid() = from_user);
