# Rise Phase 5c — Live crew status (design)

**Date:** 2026-07-18
**Status:** Drafted (build-against-the-contract; same offline-first-additive pattern as 5a/5b). Builds on 5a (auth, device-verified) + 5b (crew, merged).
**Builds on:** the merged account + crew layers. Sub-project 5c of the social layer; push/nudges (5d) and leaderboard/gifts (5e) are later.

## Goal

Show each crew member's **live status** — asleep / waking / awake — in the Crew tab, updating in real time via Supabase Realtime. Your own status is derived on-device from your real alarm/wake activity and published; you see your crew's statuses stream in. Purely additive — nothing on the alarm path changes, and the app still builds/runs with no backend.

## Non-negotiable constraints (inherited)

- **Offline-first stays sacred.** Status derivation reads alarm/wake state that already exists locally; publishing is best-effort and never blocks or touches the ring/alarm path. No existing local test may break.
- **Degrades gracefully.** Unconfigured/signed-out → `statusServiceProvider` yields a `DisabledStatusService` (no publish, empty crew statuses); the Crew UI simply shows no status dots. The app builds + runs + passes all tests with zero credentials.
- `flutter_riverpod` 2.6.1; "Mono" tokens; injectable-service + fake pattern.
- The real `SupabaseStatusService` (incl. Realtime) + SQL/RLS are **build-verified + review-verified**; the enum/derivation/fake/providers/UI are **unit/widget-tested**.

## The status model (honest by design)

Actual sleep is **not** detected. Status is derived from real alarm/wake signals; "asleep" is a presence heuristic, not sleep tracking.

`enum CrewStatus { asleep, waking, awake, unknown }`

Pure function (`lib/domain/crew_status.dart`), fully unit-tested:
```dart
CrewStatus deriveStatus({
  required DateTime now,
  DateTime? nextAlarmAt,        // soonest enabled alarm fire time (UTC), or null
  required bool hasOpenWakeEvent,
  DateTime? lastDismissedAt,    // most recent dismissal (UTC), or null
});
```
Rules, in order (constants named + documented; tunable):
1. `hasOpenWakeEvent` → **waking** (an alarm is firing / being dismissed right now — precise).
2. `lastDismissedAt` within the last **4h** → **awake** (recently got up).
3. `nextAlarmAt` in `[now, now + 10h]` AND (`lastDismissedAt == null` OR older than **8h**) → **asleep** (a morning alarm is coming and they haven't been up recently).
4. otherwise → **unknown** (no imminent alarm / not recently active → no status dot).

Documented limitation: someone with a daytime alarm within 10h who hasn't been active in 8h shows "asleep"; a nap doesn't. This is acceptable for v1 — status is a best-effort presence signal.

## Architecture

**`StatusService`** (injectable interface + impls) — `lib/data/status/status_service.dart`:
```dart
abstract interface class StatusService {
  Stream<Map<String, CrewStatus>> watch(); // userId -> status for my crew, live
  Map<String, CrewStatus> get current;
  Future<void> publish(CrewStatus status);  // upsert my own status; best-effort
}
```
- `SupabaseStatusService` — upserts my `statuses` row; subscribes to the `statuses` table via Realtime (RLS delivers only my crew's + own rows) and re-emits a `userId -> CrewStatus` map. **Build-verified only.**
- `FakeStatusService` — in-memory (seedable map + records published values), for tests.
- `DisabledStatusService` — empty map, `publish` is a no-op (never throws) so unconfigured callers are safe.

Providers (`lib/ui/state/status_providers.dart`): `statusServiceProvider` (Supabase when configured else Disabled); `crewStatusesProvider = StreamProvider<Map<String, CrewStatus>>` off `watch()`.

**`StatusPublisher`** (`lib/data/status/status_publisher.dart` + a provider): watches `nextOccurrenceProvider` + `wakeEventsProvider`, computes `deriveStatus`, and calls `publish` when the derived status **changes** (deduped) — plus once on app resume. Best-effort; a publish failure is swallowed. A small widget (`StatusPublisherHost`) mounted in the app shell drives it while signed in. Tested with fakes (derivation → publish-on-change).

## Data model (Supabase) — `supabase/migrations/0003_statuses.sql`

- `statuses(user_id uuid primary key references auth.users on delete cascade, status text not null check (status in ('asleep','waking','awake','unknown')), updated_at timestamptz not null default now())`.
- **RLS:** a user may `insert`/`update`/`select` **their own** row; and may `select` the row of anyone they have an **accepted** friendship with (reuse the friendship existence check, accepted only — you see your crew's status, not pending strangers').
- **Realtime:** add `statuses` to the `supabase_realtime` publication so row changes stream to subscribers (RLS still gates what each client receives).
- Upsert helper: the client upserts `{user_id: me, status, updated_at: now()}` on conflict `user_id`.

## UI

- **Crew tab** (`crew_screen.dart`): each `CrewMember` row (friends + incoming + outgoing) shows a small **status dot** + label from `crewStatusesProvider[member.id]` — asleep (muted/indigo), waking (amber = `RiseColors.waking`), awake (green = `RiseColors.positive`), unknown (no dot). A tiny legend under the "Your crew" header.
- Your own status is not shown in the crew list (it's your crew), but the derivation/publish runs whenever you're signed in.
- The alarm/home/stats UI is untouched.

## Error handling

- Publish failure (offline, backend down) → swallowed; status just goes stale. Never affects the alarm.
- Realtime disconnect → the stream degrades to the last-known map; a reconnect re-fetches. (Reconnize robustness is build-verified; device test confirms.)

## Testing strategy

- **Derivation:** `deriveStatus` truth table across all four states + boundaries (unit).
- **Service (fake):** `publish` records; `watch` emits the seeded/updated map; disabled is a safe no-op.
- **Publisher:** derivation changes → `publish` called once per change (deduped); no change → no publish.
- **Providers:** `crewStatusesProvider` reflects the fake; unconfigured → Disabled, empty.
- **UI (widget):** a crew member with each status renders the right dot/label; unknown → none.
- **SQL/RLS/Realtime:** review-verified + user-applied; the setup guide adds a two-account live-status smoke test.

## Deliverables the user applies

`docs/superpowers/social/2026-07-18-supabase-setup-5c.md`: apply `0003_statuses.sql`; enable Realtime on `statuses`; a two-account smoke test (A's status changes → B sees it update live within a couple seconds).

## Out of scope (5c)

Push notifications / nudges when a friend sleeps through (5d), leaderboard/gifts/voice clips (5e), an explicit "going to bed" toggle, per-friend status history, presence/last-seen beyond the four states, snooze-count in status.
