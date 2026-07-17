# Rise Phase 4b — Snooze budget + wake-up check (design)

**Date:** 2026-07-17
**Status:** Drafted from brainstorming (both features together; wake-check = notification-then-escalate, default on; snooze + wake-check timings configurable — all approved by user); pending user spec review.
**Builds on:** Phase 4a (merged): the `wake_events` log, `snoozeCount` column, and the open-event model. Local only. Wake-check native is **Android-only** for now (the Pigeon contract is extended; the iOS impl lands with the iOS engine, Plan 2 C+D).

## Goal

Close the behavioral loop: a **snooze budget** (shrinking durations, then a mission is required) and a **"still up?" wake-up check** that re-fires the alarm if the user dismisses and falls back asleep. Both timings are user-configurable via a new Settings screen.

## Approved decisions (brainstorming)

- Snooze + wake-check ship **together** in 4b.
- Wake-check: after dismissal, a **"Still up?" notification** with an "I'm up" action; ignored for **100 s** → the alarm **re-fires with its mission**. **Default on.**
- **Configurable now:** snooze count + durations, and the wake-check delay — edited in a Settings screen.
- Snooze mechanism (pre-designed in the 4a spec): `snoozedUntil` on the alarm drives `nextOccurrence`, integrating snooze into the existing reconcile/`setAlarmClock` path — **no parallel scheduler**.

## Snooze

### Data
- Add `snoozedUntil` (nullable, UTC) to `Alarm` + the `alarms` table (schema **v3 → v4**, idempotent migration, same multi-isolate-safe pattern).
- `nextOccurrence` / `desiredOccurrences`: when `snoozedUntil != null && snoozedUntil > now`, the alarm's next firing **is** `snoozedUntil`; otherwise the normal schedule. So a snoozed alarm is armed for `snoozedUntil` by the ordinary reconcile, survives reboot (boot reconcile re-arms; a `snoozedUntil` in the past is recovered by the existing missed-alarm path), and needs no new native code.

### Budget (configurable)
- `RiseSettings.snoozeMaxCount` (0–5, default **3**) and `snoozeFlatMinutes` (0 = shrinking mode, default 0). Duration for snooze N (0-indexed): `snoozeFlatMinutes > 0 ? snoozeFlatMinutes : [9, 5, 3, 2, 1][N]`.
- Snooze is offered while the open event's `snoozeCount < snoozeMaxCount`. After the budget is spent the Snooze button disappears — the user must dismiss (mission if the alarm has one). `snoozeMaxCount == 0` disables snooze entirely.

### Ring-screen action
- A **Snooze button** below the dismiss gate, shown while `snoozeCount < snoozeMaxCount`, labelled with the next duration (e.g. "Snooze 9 min"). Tapping it:
  1. bumps `snoozeCount` on the **open** wake event (the event stays open — final `onTime` is still measured from the *first* ring, so snoozing risks the streak, by design);
  2. sets `alarm.snoozedUntil = now + duration` and persists;
  3. `stopRinging` (silence) + `reconcileNow` (arms `setAlarmClock` at `snoozedUntil`);
  4. pops the ring screen.
- On **dismissal**, `snoozedUntil` is cleared (the alarm returns to its normal schedule) alongside the existing `recordDismissed`.

## Wake-up check

### Settings
- `RiseSettings.wakeCheckEnabled` (bool, default **true**) and `wakeCheckDelayMinutes` (1–30, default **5**). The 100 s response window is a fixed constant for v1.

### Flow
1. On a **real dismissal** (not a snooze), if `wakeCheckEnabled`, Dart calls `scheduleWakeCheck(nativeAlarm, checkAt = now + wakeCheckDelayMinutes)`.
2. Android arms two OS events (via `AlarmManager`, so they work with the app dead): a **notification trigger** at `checkAt`, and a **re-fire** at `checkAt + 100 s`.
3. At `checkAt`, `WakeCheckReceiver` posts a high-priority **"Still up?"** notification with an **"I'm up"** action.
4. **"I'm up"** → a broadcast → a confirm receiver that **cancels the re-fire** + dismisses the notification. (Swiping/ignoring does nothing — you must confirm.)
5. If 100 s pass with no confirm, the **re-fire** fires: it re-enters the existing ring path (`AlarmReceiver` → foreground service → `RingActivity`) for the same alarm, so it rings with the alarm's mission (RingScreen reads the mission from the DB) and records its own wake event.
6. `cancelWakeCheck(alarmId)` fires if the alarm is deleted, the feature is turned off, or a fresh dismissal supersedes a pending check.

### Native surface (Android; iOS deferred)
- Pigeon `AlarmHostApi` gains `scheduleWakeCheck(NativeAlarm alarm, int checkAtEpochMs)` and `cancelWakeCheck(int alarmId)`. Regenerate `alarm_api.g.dart`/`AlarmApi.g.kt`/`AlarmApi.g.swift` (Swift side gets a stub throwing `unsupported`/no-op until the iOS engine exists).
- New Kotlin: `WakeCheckReceiver` (posts the notification), a confirm/​"I'm up" `BroadcastReceiver` (cancels the re-fire + notification), and a **"Wake check" notification channel**. The re-fire is armed through the existing `AlarmScheduler`/`AlarmReceiver` path but with a **distinct request-code namespace** (offset from the normal alarm PendingIntent) so it never collides with the alarm's ordinary scheduled instant. Register the two receivers in the manifest.
- The re-fire's `NativeAlarm` is carried in its PendingIntent (same serialization the normal scheduler uses).

## Settings storage + UI

- Extend `AppSettings` (SharedPreferences) with the new keys + async setters (alongside `onboardingComplete`).
- A `RiseSettings` immutable snapshot (all keys) exposed by a `settingsProvider` (`StateNotifierProvider<SettingsController, RiseSettings>`); `SettingsController.setX` persists via `AppSettings` and emits new state.
- A new **Settings screen** reached from a "Settings" row in Profile: a **Snooze** section (max-count stepper 0–5; length mode: Shrinking 9→5→3 / flat 5 / 10 / 15 min) and a **Wake-up check** section (on/off toggle; delay stepper 1–30 min, default 5). The snooze/wake-check logic reads the current `RiseSettings`.

## Edge cases

- **Snooze past reboot** — `snoozedUntil` persists; boot reconcile re-arms it (or missed-recovery rings a past one). No special handling.
- **App dead during the wake-check window** — the notification + re-fire are OS-scheduled (`AlarmManager`), so they fire regardless. This is the whole point.
- **Alarm deleted mid-check** — deleting an alarm calls `cancelWakeCheck(id)`; a re-fire whose alarm is gone rings nothing meaningful, so cancel is important. The RingScreen already tolerates a missing alarm (falls back to slide-to-wake).
- **Wake-check disabled while one is pending** — turning the toggle off cancels any scheduled check (best-effort; a check already armed for a past dismissal is cancelled on the next dismissal at latest).
- **Snooze + on-time** — snoozing keeps the event open; the final dismissal's `onTime` is `dismissed − firstRingAt ≤ 15 min`, so enough snoozing turns a wake into a miss. Intended.
- **Notification permission off** — the "Still up?" notification silently won't show; the re-fire (a full alarm) still fires (it doesn't depend on the notification), so the safety net degrades to "always re-rings" rather than failing open. Acceptable and honest.
- **Re-fire recording** — the re-fire opens a *new* wake event (the first was finalized on dismissal); the day already succeeded if the first dismissal was on-time, so a wake-check re-ring doesn't retroactively fail the streak in v1.

## Testing strategy

- **Dart (unit/widget):** `nextOccurrence`/`desiredOccurrences` honor `snoozedUntil` (fires at it; ignores a past one); the snooze budget picks the right duration per count and hides the button at the cap; snooze bumps `snoozeCount` + sets `snoozedUntil` + reconciles (fake platform); dismissal clears `snoozedUntil`; `RiseSettings`/`SettingsController` round-trip through mock SharedPreferences; the Settings screen renders + edits; the ring screen shows/hides Snooze per budget and per `snoozeMaxCount == 0`.
- **Native scheduling is device-verified** (as in Plan 1) — unit tests can't exercise `AlarmManager`/receivers/notifications. The on-device protocol covers: snooze shrinking + budget exhaustion; the "Still up?" notification appearing at the delay; "I'm up" cancelling the re-fire; ignoring it → re-ring with mission; disabling the feature; and reboot during a snooze.

## Interfaces / consistency with Phase 4a

- `snoozeCount` (added in 4a, always 0 there) now increments on snooze; the Stats week-chart's snooze display becomes meaningful. `WakeRecorder` gains a way to bump `snoozeCount` on the open event.

## Out of scope (4b)

- iOS wake-check native (waits for the iOS engine). Per-alarm snooze policy (stays global). Making a slept-through wake-check penalize the streak. Any "wake-up check" analytics beyond the existing wake-event log. Goal-locking, gentle mode.
