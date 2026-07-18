# Phase 5c — Live crew status — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show each crew member's live status (asleep / waking / awake) in the Crew tab, updating in real time via Supabase Realtime; derive and publish your own status from real alarm/wake activity — purely additive to the local alarm app.

**Architecture:** A pure `deriveStatus` function + an injectable `StatusService` (Supabase Realtime impl + a fake) make the whole thing testable without a backend. A `StatusPublisher` watches alarm/wake providers and publishes on change. `statusServiceProvider` gates on config. Same pattern as 5a/5b.

**Tech Stack:** Flutter 3.35 / Dart 3.9, flutter_riverpod 2.6.1, supabase_flutter 2.16.0 (Realtime), Postgres/RLS, "Mono" design.

## Global Constraints

- **Offline-first is sacred:** derivation reads already-local alarm/wake state; publishing is best-effort and never touches the ring/alarm path. No existing local test may break.
- **Degrade gracefully:** unconfigured/signed-out → `DisabledStatusService` (no publish, empty statuses); the Crew UI shows no dots. Builds/runs/passes with zero credentials.
- `flutter_riverpod` 2.6.1 (2.x API only); "Mono" tokens; injectable-service + fake pattern.
- The real `SupabaseStatusService` (Realtime) + SQL are **build-verified + review-verified**; enum/derivation/fake/providers/UI are **unit/widget-tested**.
- `database.g.dart` gitignored; `alarm_api.g.dart` committed. **TDD, teeth-first.** Branch `phase5c`.

## File Structure

- `lib/domain/crew_status.dart` — `CrewStatus` enum + `deriveStatus(...)` (Task 1).
- `lib/data/status/status_service.dart` — interface + `FakeStatusService` + `DisabledStatusService` (Task 2).
- `lib/data/status/supabase_status_service.dart` — `SupabaseStatusService` (Realtime) (Task 4).
- `lib/data/status/status_publisher.dart` — `StatusPublisher` + host (Task 5).
- `lib/ui/state/status_providers.dart` — `statusServiceProvider`, `crewStatusesProvider` (Task 3).
- `lib/ui/screens/crew_screen.dart` — status dots per member (Task 6).
- `supabase/migrations/0003_statuses.sql`, `docs/superpowers/social/2026-07-18-supabase-setup-5c.md` (Task 7).

---

## Tasks (full code written into each brief just before dispatch — same flow as 5a/5b)

- **Task 1 — Enum + derivation** (`crew_status.dart`): `enum CrewStatus { asleep, waking, awake, unknown }` + pure `deriveStatus({now, nextAlarmAt?, hasOpenWakeEvent, lastDismissedAt?})` per the spec's 4 ordered rules (named constants: WAKING=open event; AWAKE ≤4h since dismiss; ASLEEP if next alarm ∈ [now, now+10h] and last dismiss null/older-than-8h; else UNKNOWN). Truth-table unit tests incl. boundaries.
- **Task 2 — `StatusService` + fakes** (`status_service.dart`): interface (`watch()→Stream<Map<String,CrewStatus>>`, `current`, `publish(CrewStatus)`); `FakeStatusService` (seedable map + a broadcast `watch`; `publish` records the last published value + can be asserted; a way to inject a crew status change for the stream test); `DisabledStatusService` (empty map, `publish` no-op, never throws). Unit tests.
- **Task 3 — Providers** (`status_providers.dart`): `statusServiceProvider` (Supabase when `SupabaseConfig.isConfigured` else Disabled, `ref.onDispose`); `crewStatusesProvider = StreamProvider<Map<String,CrewStatus>>`. Provider tests with the fake.
- **Task 4 — `SupabaseStatusService`** (`supabase_status_service.dart`): `publish` upserts `{user_id: me, status, updated_at}` on conflict `user_id`; `watch` primes from a select of readable `statuses` rows then subscribes via `supabase.channel(...).onPostgresChanges(event: all, schema: public, table: statuses, callback:)` and re-emits the merged `userId->status` map; best-effort (never throws into the stream); `dispose` removes the channel + closes. **Build-verified only** (adapt the exact Realtime API to the installed `supabase_flutter`/`realtime_client` version so `flutter build apk` compiles).
- **Task 5 — `StatusPublisher`** (`status_publisher.dart`): a small object/host that reads `nextOccurrenceProvider` + `wakeEventsProvider` (+ `accountProvider` to gate on signed-in), computes `deriveStatus`, and calls `statusService.publish` only when the derived status changes (deduped via a stored last value); a `StatusPublisherHost` widget mounted in `app_shell` that also republishes on `AppLifecycleState.resumed`. Tests with fakes: a derivation change publishes once; no change → no publish; signed-out → no publish.
- **Task 6 — Crew UI status dots** (`crew_screen.dart`): each member row shows a status dot + label from `crewStatusesProvider.value?[member.id] ?? unknown` — waking=`RiseColors.waking`, awake=`RiseColors.positive`, asleep=a muted indigo token, unknown=no dot; a small legend. Widget tests: each status renders the right dot/label; unknown → none; existing crew tests still pass.
- **Task 7 — SQL + setup + verify + merge** (`0003_statuses.sql`, `2026-07-18-supabase-setup-5c.md`): `statuses` table + RLS (own row rw; select a crew member's row only for an ACCEPTED friendship) + add `statuses` to the `supabase_realtime` publication; setup guide with a two-account live-status smoke test. Then `flutter test` green, `flutter analyze` clean, `flutter build apk --release --dart-define-from-file=rise.env.json` builds; final whole-branch review; merge `phase5c` → `main`; device-test with the user.
