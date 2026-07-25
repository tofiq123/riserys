# Group challenges — streak race (design, 2026-07-25)

The big Group-1 item. Decision (locked): **streak race** — a crew group runs a
race where everyone keeps their daily wake streak alive; the challenge tracks
who's still standing (streak intact since the gun) and who's out.

## Principle: lean on data we already sync
Each user's current wake streak is already computed by the streak engine and
synced to Supabase `stats` (Phase 4a + 5e), and the group leaderboard already
ranks group members by streak (0006). So a streak race needs **no per-member
challenge bookkeeping** — only a marker for *when the race started*. Standings
are derived from (each member's current streak) + (days since start).

## Data — migration `0013_group_challenges.sql`
```
group_challenges(
  id          uuid pk default gen_random_uuid(),
  group_id    uuid not null references groups(id) on delete cascade,
  kind        text not null default 'streak_race' check (kind in ('streak_race')),
  started_at  timestamptz not null default now(),
  created_by  uuid not null references auth.users(id),
  ended_at    timestamptz            -- null = active
)
```
- **One active race per group:** partial unique index on `(group_id) where ended_at is null`.
- Immutability guard trigger (mirrors 0006): only `ended_at` may change.

## RLS (mirrors 0006 — via the existing SECURITY DEFINER helpers, no recursion)
- **SELECT:** group members — `is_group_member(group_id, auth.uid())`.
- **INSERT:** group **owner** only — `is_group_owner(group_id, auth.uid())` AND
  `created_by = auth.uid()`.
- **UPDATE:** owner only (to set `ended_at`); guard trigger freezes everything else.
- **DELETE:** owner only (plus the FK cascade when the group is disbanded).

## Domain logic (pure, testable) — `group_challenge.dart`
`challengeStandings({required DateTime startedAt, required DateTime now,
required List<LeaderboardEntry> members})` →
- `daysElapsed = whole UTC days between startedAt and now`.
- A member is **in** when `streak >= daysElapsed` (kept the streak the whole
  race), else **out**. Day 0 → everyone in.
- Sort: in-first, then streak desc, then name. Returns `[(member, inRace)]`.
- Late joiners (streak < daysElapsed) simply show "out" until they catch up —
  acceptable for a v1 social game; documented.

## Service + UI
- `GroupService`: `startChallenge(groupId)`, `endChallenge(id)`, and the active
  challenge exposed on the group stream.
- Group detail screen — a **"Streak race"** section: no race → owner sees "Start
  a streak race"; active → "Day N", the standings (🔥 in · streak; 💤 out), and
  the owner can "End race".

## Red lines / tone
Kind, not punitive: "out" is 💤/gentle, never a shaming push (no notification
fires for breaking). A race is opt-in per group — only the owner starts it.

## Constraints (flagged, not deferred)
- Migration `0013` — **you apply + review the RLS**; build-verified only (no live
  backend in CI), like the others.
- Start-in-one-account / see-standings-in-another needs the **2-device test**.

## Build order
1. Migration `0013` (+ self-review the RLS).
2. `challengeStandings` domain fn + tests.
3. `GroupService` methods + fakes.
4. Group-detail "Streak race" UI + a widget test.
