# Overlapping alarms: ring queue

**Status:** approved 2026-08-05 from conversational brainstorming (no mockups —
this is a native/data-flow change with one small screen addition).
**Closes:** the "Overlapping alarms" deferred item in
`docs/superpowers/plans/2026-07-15-foundations-android-alarm-engine.md:2990`,
implementing the behavior the original spec already promised at
`docs/superpowers/specs/2026-07-15-rise-alarm-app-design.md:212`
("Priority queue: earliest rings; next queues after dismissal").

## Why

Today `AlarmService` holds a single `ringingAlarmId` slot. When a second alarm
fires while one is already ringing — whether they were set for the identical
minute or the first alarm just hasn't been dismissed yet — `onStartCommand`
unconditionally tears down the first alarm's audio, vibration, and wake lock
and replaces it with the second (`AlarmService.kt:51-60`). `main.dart` mirrors
this with `pushReplacement` on `RingScreen` (`main.dart:238-276`). The result:
the alarm that fires second always wins, the first alarm's ring — and any
in-progress mission — is silently discarded, and nothing queues.

This is a real user-facing gap, not a hypothetical: any two alarms set close
together (a backup alarm, two people's alarms sharing a phone, a snooze that
overlaps a second alarm's fire) hit it.

## Scope

In: `AlarmService.kt`, `AlarmReceiver.kt` (unchanged, confirmed no change
needed), `pigeons/alarm_api.dart` (+ generated `alarm_api.g.dart` /
`AlarmApi.g.kt`), `lib/main.dart`'s ring reconciliation, `lib/ui/screens/ring_screen.dart`.

Out: iOS (no equivalent single-service ring model — 26+ delegates overlap
handling to AlarmKit itself; the 16–25 fallback is a notification burst, not a
foreground service — nothing here applies until that platform's own compile
pass). Out: snooze budget/policy, mission design, alarm creation/validation —
unchanged.

## Behavior

- **Overlap is defined broadly**, matching the spec's own wording: any alarm
  that fires while `AlarmService` is already ringing something else, not only
  alarms scheduled for the identical instant.
- **Queue is FIFO, arbitrary depth.** A third or fourth overlapping alarm
  queues the same way a second does — no special-casing, no cap.
- **The ringing alarm is never interrupted by a later fire.** Its audio,
  vibration, wake lock, and `RingScreen` (including in-progress mission state)
  continue completely untouched while others queue behind it.
- **Dismissing the ringing alarm advances the queue**: the next queued alarm
  starts ringing immediately, with the same treatment (gentle volume ramp,
  chosen sound/vibration pattern) a fresh ring gets.
- **Snoozing the ringing alarm also advances the queue.** Snoozing already
  stops-then-rearms the snoozed alarm for later; the queued alarm does not
  wait out that snooze window — it starts ringing as soon as the snooze call
  ends the current ring session.
- **The ring screen shows a quiet, informational indicator** of the next
  queued alarm ("next: `<label>` queued") — no interaction, not tappable, no
  way to skip it early. Only the immediate next is shown even if more than one
  is queued.
- **The queue is persisted**, not just held in memory, so a rare OS kill of
  the foreground service mid-ring cannot silently drop a queued alarm.

## Architecture

The queue lives in `AlarmService`'s companion object next to the existing
`ringingAlarmId`. Every path that starts a ring — `AlarmReceiver` on a real
fire, and `AlarmScheduler.ringNow` (used for missed-alarm recovery, itself
routed through the same receiver/service path) — converges on
`AlarmService.onStartCommand`, so the queue needs exactly one guard there:

- `ringingAlarmId == null` → ring immediately, exactly as today.
- `ringingAlarmId != null` and the incoming id differs → append to the queue,
  call `startForeground()` again with the *unchanged* current notification
  (required to satisfy Android's foreground-service start contract for this
  new `startForegroundService()` call — content is deliberately not updated,
  so nothing about the active ring visibly or audibly changes), and return
  without touching audio/vibration/wake lock.

Advancing the queue replaces the unconditional `AlarmService.stop(context)` in
the dismiss/snooze path: when the alarm being stopped matches
`ringingAlarmId` and the queue is non-empty, dequeue the head and re-run the
ring-start logic for it instead of stopping the service; only stop when the
queue is empty.

Dart learns about the queue the same way it learns about the current ring —
polling, no push channel — via a new `AlarmHostApi.getQueuedAlarmId(): int?`,
peeking the queue head exactly as `getRingingAlarmId()` peeks the current
ring. `main.dart`'s `_reconcileRingScreen` stops treating "a different id is
now known" as a reason to `pushReplacement`; it reacts only when
`getRingingAlarmId()` itself changes, which under the new native behavior
only happens on a genuine queue advance, never a clobber.
`_checkColdStartRing` polls both ids in the same call so the chip is correct
immediately after cold start or resume, matching the existing rationale for
why that poll exists at all (`RingActivity` is `singleInstance`; a queue
advance while backgrounded delivers no signal that reaches Dart on its own).

## Components & data model

**Native (`AlarmService.kt`):**
- `data class RingRequest(val id: Int, val label: String, val sound: String, val vibrate: Boolean, val vibrationPattern: String)` —
  the same fields `onStartCommand` already reads off the `Intent`, captured
  instead of used-and-discarded.
- `companion object` gains `val ringQueue: MutableList<RingRequest>`.
- `advanceQueue()`: pops the head (if any) and re-enters the ring-start logic
  for it; called from the dismiss/snooze path in place of the unconditional
  stop.
- Queue persistence: written to `SharedPreferences` on every enqueue/dequeue
  (a simple serialized list of `RingRequest`), restored in `onCreate()` so a
  process restart via `START_REDELIVER_INTENT` (which only redelivers the
  *last* `onStartCommand` Intent, not the whole queue) can rebuild the rest of
  the queue instead of losing it.

**Bridge (`pigeons/alarm_api.dart`):**
```dart
/// The next alarm waiting behind the one currently ringing, or null.
/// Peeks like [getRingingAlarmId] — does not clear state, poll it.
int? getQueuedAlarmId();
```
Regenerates `lib/data/native/alarm_api.g.dart` and
`android/app/src/main/kotlin/com/riseapp/rise/AlarmApi.g.kt` via the existing
Pigeon codegen step.

**Dart (`RingScreen`):** takes/polls `queuedAlarmId` alongside `alarmId`,
resolves its label via the existing alarm lookup, and renders a small static
chip under the alarm label when non-null. No new animation, no interaction.

## Data flow

**Two alarms overlap:** A fires → `ringingAlarmId == null` → rings normally,
`ringingAlarmId = A`. B fires (same instant or minutes later) →
`ringingAlarmId = A` already set → B appended to `ringQueue`, A untouched.
Dart's poll of `getRingingAlarmId()` still returns A; `getQueuedAlarmId()` now
returns B. `RingScreen` for A stays mounted, mission progress intact; the
"next: B" chip appears.

**Dismiss advances the queue:** user dismisses A → `stopRinging(A)` → native
confirms A is still `ringingAlarmId` → queue non-empty → `advanceQueue()`
pops B, rings it, `ringingAlarmId = B`. Dart's next poll sees
`getRingingAlarmId()` change from A to B → `_reconcileRingScreen` performs a
real `pushReplacement`, now correct because A's session has genuinely ended →
B's `RingScreen` mounts with its own mission.

**Snooze advances the queue too:** snoozing A calls the same
`stopRinging(A)` → `advanceQueue()` path (snooze already stops-then-rearms
today, so this falls out for free) → B starts immediately rather than
waiting out A's snooze window.

**Three or more:** each additional fire while `ringingAlarmId != null` simply
appends; `advanceQueue()` always pops index 0, so ordering is strictly firing
order — which tracks scheduled-time order in every realistic case, since
`AlarmReceiver` only fires at-or-after an alarm's own scheduled instant.

**Cold start / resume:** unchanged pattern, one more field polled alongside
the existing one.

## Error handling

- **Foreground-service start contract:** satisfied by re-calling
  `startForeground()` with A's unchanged notification on a queued (not yet
  ringing) `onStartCommand` — mechanical, not architecturally uncertain.
- **Ring-start failures:** already hardened. `startAudio` catches
  `MediaPlayer` failures and falls back to the bundled default sound
  (`AlarmService.kt:152-160`); a queued alarm advancing through the same path
  inherits that guarantee.
- **Process death with a non-empty queue:** the one new failure category this
  feature introduces (today, only a single ringing alarm's state can be lost
  this way; a queue adds queued-but-not-yet-ringing alarms to what could be
  lost). Mitigated by persisting the queue, not just the current ring, so a
  restart can restore it rather than silently drop what was queued.
- **Polling races:** none new. `getQueuedAlarmId`/`getRingingAlarmId` both run
  on the service's main thread, same as today's single-id polling. The
  existing `_reconcileRingScreen` guard (`if (id == _shownRingId) return;`)
  already no-ops any duplicate delivery.

## Testing

- **Kotlin (`AlarmService`):** queue logic reviewed and exercised where
  testable in isolation from the Android framework — enqueue-while-ringing
  appends instead of clobbering, `advanceQueue()` pops FIFO and re-enters the
  ring-start path, persistence round-trips (write on enqueue/dequeue, restore
  in `onCreate`). Per this repo's existing constraint, native alarm-path
  changes are review-verified plus device-verified rather than covered by a
  Windows-runnable automated suite.
- **Dart (`RingScreen` + `main.dart`):** widget tests with a fake
  `AlarmHostApi` (extending the existing `getRingingAlarmId` fake pattern to
  also stub `getQueuedAlarmId`) covering: chip appears/resolves correctly when
  a queued id is present; chip absent when null; `_reconcileRingScreen` does
  *not* replace the screen when only the queued id changes (the core
  regression this feature fixes); it *does* replace when the ringing id
  itself changes; `RingScreen`'s mid-mission state survives a queued-id
  change, proving the ringing alarm's session isn't torn down.
- **Device verification (required):** two physical alarms a few minutes
  apart, each with a mission — confirm A rings uninterrupted with B's chip
  showing, dismissing A hands off to B cleanly (A's mission state gone as
  expected — new session — but A's audio never glitching during the overlap),
  and snoozing A also hands off to B immediately. Recorded in
  `docs/superpowers/reliability/` per existing convention.
