# Phase 4a (wake data, streaks & stats) — on-device verification

**Date:** 2026-07-17
**Device:** Samsung Galaxy S24 Ultra (SM S928B), Android 16 (API 36)
**Build:** `phase4a` HEAD `dca313a`, release APK, installed with `adb install -r` over the existing Plan-3 install (so the **v2→v3 Drift migration ran on live data** with existing alarms).

## Outcome: PASS — verified by the user

The local wake-data behavioral loop works end to end on the physical device:

- **Migration on live data** — the app opened cleanly over the existing install; the `wake_events` table was added by the v2→v3 migration and existing alarms were preserved (no data loss, no crash).
- **Record → streak → UI loop** — setting an alarm, letting it ring on a locked phone, and dismissing on time produced a wake event that flipped the Home **streak pill** to 1, and the **Stats** screen showed today on-time ("On time 1 of 1", green calendar cell).
- **Miss handling** — a late/skipped dismissal registered as a miss (red) and reset the streak as designed.
- **No regressions** — the ring screen is unchanged from Plan 3 (dismiss only, no snooze yet — that's Phase 4b); rings-through-silent+locked, mission gating, and reboot re-arm all still hold.
- **Sleep→Stats tab** and the streak-pill deep-link both work.

## Notes / follow-ups (not blocking merge)

- Deferred cosmetic minors from the final whole-branch review: two lateness metrics (`onTime` uses firstRingAt; the chart bar uses scheduledAt — cosmetic, the streak never uses scheduledAt, and the chart clamps); a pending-"today" color mismatch between the calendar and week chart (transient, self-corrects on the on-time dismiss); `streakProvider` not re-evaluating at a midnight rollover while the app is left open (self-heals on next event/relaunch). See `.superpowers/sdd/progress.md`.
- **Phase 4b** (snooze budget + "still up?" wake-up check) is the next increment; it builds on the wake-event log, `snoozeCount`, and the open-event model established here.
- Still open elsewhere: custom launcher icon, Plan 1 Task 13 multi-day soak, Plan 2 Groups C+D (iOS engine).
