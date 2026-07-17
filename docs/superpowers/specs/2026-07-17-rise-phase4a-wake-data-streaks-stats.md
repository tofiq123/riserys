# Rise Phase 4a — Wake data, streaks & stats (design)

**Date:** 2026-07-17
**Status:** Drafted from brainstorming (scope + streak rule + decomposition approved by user); pending user spec review.
**Builds on:** Plan 3 (alarm-core UI, merged to `main`). Everything here is **local** — no auth/cloud (that is Phase 5). Designed so Phase 5 can later sync the local `wake_events` to the Supabase `wake_events` table.

## Goal

Make the app's wake data real: record a **wake event** every time an alarm fires and is dealt with, compute a **streak** from those events, and surface it — the Home streak pill goes live and a **Stats** view shows history. This is the first of two Phase-4 increments; **Phase 4b** (snooze budget + "still up?" wake-up check) builds on the data model and recording lifecycle defined here.

## Principles (from the master spec §Behavioral model)

- **Consistency is the hero metric** — the streak rewards *waking on time*, not app opens.
- **Streaks with forgiveness** — a missed day consumes an earned *freeze* before it breaks the streak; quitting after a miss is the real failure, not the miss itself.
- **No shame, no health-scare framing** in any stat copy.

## Approved decisions (brainstorming)

- **Scope:** the full behavioral loop, split into **4a** (this spec: data + streaks + stats UI, no new native code) then **4b** (snooze + wake-up check).
- **Streak success rule:** a day succeeds if the alarm was **dismissed on time** — fully dismissed within a **15-minute grace window** after it first rang. Snoozing (4b) is allowed but eats into that window.
- **Judgment calls carried forward** (open to change at spec review): stats live in the **"Sleep" tab repurposed as "Stats"** (empty Sleep stub is dead weight; real sleep tracking is deferred); the Home streak pill deep-links there.

## Data model

### New Drift table `WakeEvents` (schema v2 → v3)

One row per **logical firing** of an alarm (in 4a, one ring→dismiss; in 4b, one row spans its snoozes and any wake-check re-fire).

| Column | Type | Meaning |
|---|---|---|
| `id` | int PK autoinc | |
| `alarmId` | int | The alarm that fired. Kept even if the alarm is later edited/deleted. |
| `scheduledAt` | DateTime (UTC) | The instant the alarm was scheduled to fire (computed from the alarm's hour/minute on the ring's local day). |
| `firstRingAt` | DateTime (UTC) | When the ring actually started (this firing). |
| `dismissedAt` | DateTime? (UTC) | When finalized. **Null = still open / never dismissed = a miss.** |
| `method` | text? | `'mission'` \| `'slide'` \| `'safety'` \| null. |
| `snoozeCount` | int (default 0) | Always 0 in 4a; 4b increments. |
| `missionFailures` | int (default 0) | 0 in 4a; wired later. |
| `onTime` | bool (default false) | Set at finalize: `dismissedAt − firstRingAt ≤ 15 min`. |
| `label` | text | Snapshot of the alarm label at ring time (stats survive edits/deletes). |

**Migration** mirrors the existing idempotent, multi-isolate-safe pattern (foreground/ring/boot isolates can race the first upgrade). Because this adds a *table* (not a column), the guard checks `sqlite_master` for the table before creating it:

```
onUpgrade: if (from < 3) { if (!await _tableExists('wake_events')) m.createTable(wakeEvents); }
```
Add a `_tableExists(name)` helper alongside the existing `_columnNames` (both read sqlite's own schema). `schemaVersion` → 3. `wake_events` is **independent** of `alarms` — deleting an alarm does not delete its events.

### Domain entity `WakeEvent`

Immutable value object mirroring the row (`==`/`hashCode`/`copyWith`), with a getter `DateTime localDay` (the local calendar day of `firstRingAt`, used for grouping) and `Duration? timeToWake` (`dismissedAt − scheduledAt`, for the wake-vs-set delta).

## Recording lifecycle

The event is **opened when the ring starts** and **finalized on dismissal**. An opened-but-never-finalized event *is* the miss record — no separate miss path needed.

- **Open (ring start):** `RingScreen` (which already mounts when an alarm rings, in the app or the RingActivity engine) calls a `WakeRecorder.openRing(alarmId)` on mount. The recorder looks up the alarm (for `label`, `hour`, `minute`), computes `scheduledAt` from the alarm's time on today's local date, and:
  - if an **open** event (`dismissedAt == null`) exists for this `alarmId` within the last ~6 h, **reuses** it (no duplicate) — handles `RingScreen` re-mounts (singleInstance reuse, cold-start/resume re-checks) and sets up 4b's snooze continuation;
  - otherwise inserts a new open event with `firstRingAt = now`.
- **Finalize (dismiss):** the existing dismissal path (`dismissRingingAlarm` → after `recordDismissed`) calls `WakeRecorder.finalizeDismiss(alarmId, method)`, which finds the open event for `alarmId`, sets `dismissedAt = now`, `method`, and `onTime = (dismissedAt − firstRingAt) ≤ 15 min`. Idempotent: a second finalize for an already-closed event is a no-op.

`WakeRecorder` is a thin service over a `WakeEventRepository` (Drift), reached via a Riverpod provider; `RingScreen` gets it injected (default = real, overridable in tests) exactly like its existing `dismissAlarm` seam, so ring tests stay platform-free.

## Streak engine (pure Dart, no stored mutable counter)

A single deterministic function is the entire streak logic — recomputed from the event log every time, so it can never desync:

```
StreakStats computeStreak(List<WakeEvent> events, DateTime now, {Duration grace = 15 min, int freezeCap = 2, int earnEvery = 7})
```

Returns `{int current, int best, int freezesRemaining, Map<DateTime,DayOutcome> byDay}` where `DayOutcome ∈ {success, miss, neutral, pending}`.

**Day classification** (group events by `localDay`):
- **success** — the day has ≥1 event with `onTime == true`.
- **miss** — the day is in the **past**, had ≥1 ring, and no on-time dismissal.
- **pending** — **today**, has ≥1 open/not-yet-on-time event but no on-time success yet (does not break the streak; shown as "at risk").
- **neutral** — no events that day (no alarm rang) → skipped entirely.

**Fold** over past days oldest→newest, skipping neutral days, tracking a running success count and a freeze balance:
- success → `run++`; every `earnEvery`-th consecutive success grants a freeze (capped at `freezeCap`).
- miss → if `freezesRemaining > 0`, consume one and treat the day as *held* (run continues); else `run = 0`.
- `best` = max `run` seen. `current` = the run ending at the most recent past non-neutral day, **plus 1 if today is a success**.

Today being a **success** extends `current` immediately (pill updates the moment you wake on time); today being **pending** leaves `current` standing from yesterday; today only becomes a **miss** once it is past.

## State / providers

- `wakeEventsProvider` — `StreamProvider<List<WakeEvent>>` watching the repository.
- `streakProvider` — `Provider<StreakStats>` = `computeStreak(events, DateTime.now())`. (Tests exercise the pure function with a fixed `now`; the provider just supplies wall-clock now.)

## UI

- **Home streak pill (goes live).** Replaces the Task-7 placeholder: a flame + `current` (e.g. "🔥 5"), or a muted "Start a streak" when `current == 0`. Tapping it deep-links to Stats. Add an `onStreak` callback to `HomeScreen` (alongside `onNew`/`onEdit`/`onPreview`); the app shell switches to the Stats tab.
- **Stats screen (new).** Sections: the big **current streak** + best + **freezes remaining**; an **on-time calendar** (last ~30 days grid coloured success/miss/neutral); a **7-day chart** of wake-vs-set delta (bars) with per-day snooze count (0 until 4b); a plain-language **consistency line** ("On time 6 of the last 7 days"). All from `streakProvider` + `wakeEventsProvider`; empty state invites setting the first alarm.
- **Tab change.** The app shell's stubbed **"Sleep"** tab becomes **"Stats"** (chart/flame icon) hosting the Stats screen; the "Crew" stub stays. `_ComingSoon` stays available for Crew.

## Edge cases

- **Day boundary / timezone** — group by the **local** day of `firstRingAt` (device tz is set correctly at startup via `flutter_timezone`). A DST or travel shift just moves the boundary; accepted.
- **Deleted/edited alarm** — events are independent and carry a `label` snapshot; history persists. Editing an alarm's time doesn't rewrite past events.
- **Force-quit mid-ring** — the open event is never finalized → it becomes a miss when the day closes. Rare; accepted.
- **Multiple alarms in one day** — the day succeeds if **any** on-time event exists (lenient per-day: "you woke up today").
- **Re-mount / duplicate rings** — the ~6 h open-event reuse prevents duplicate rows for one firing.
- **Clock moved backward** — timestamps are UTC; only day-grouping uses local time; a large backward jump could mis-bucket a day. Rare; accepted for v1.
- **No installed base yet** — first upgrade to v3 on a device with existing alarms just adds the empty table.

## Testing strategy

- **Streak engine (heaviest):** pure unit tests over hand-built event lists + fixed `now` — clean streaks, a miss breaking, a freeze absorbing a miss, freeze earning at 7/cap at 2, neutral (no-alarm) days skipped, today-success vs today-pending, multi-alarm days, month/day boundaries. Each test must fail if the rule breaks (no tautologies).
- **WakeEventRepository:** open idempotency (reuse within 6 h; new after), finalize sets `onTime` correctly at the 15-min boundary (14:59 on-time, 15:01 not), finalize on a missing/closed event is a no-op.
- **Recording integration:** a ring→dismiss through `RingScreen` (fake recorder) opens then finalizes exactly one event with the right `method`.
- **UI:** Home pill shows the streak / "Start a streak"; tapping it calls `onStreak`; Stats screen renders streak, calendar, and chart from overridden providers; empty state.

## Interfaces handed to Phase 4b

- `snoozeCount` (4b increments on each snooze), `snoozedUntil` on the alarm (4b; `nextOccurrence` will fire at it), `missionFailures`, and the wake-check re-fire all **continue the same open event** via the open-event model defined here — 4b adds behavior, not a new data model.

## Out of scope (4a)

Snooze, the wake-up check, cloud sync, goal-locking, gentle mode, and any sophistication beyond a simple consistency line. Sleep tracking stays deferred (the tab is only *renamed*).
