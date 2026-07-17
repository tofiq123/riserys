# Phase 4b (snooze + wake-up check) — verification results

**Date:** 2026-07-18
**Device:** Samsung Galaxy S24 Ultra (SM S928B), Android 16 (API 36)
**Build:** `phase4b`, release APK, `adb install -r` over the existing install (exercised the v3→v4 migration on live data).

## Snooze — device-verified PASS

The snooze budget works on hardware (user-confirmed): the ring screen shows a **"Snooze 9 min"** button that shrinks **9 → 5 → 3** across successive snoozes and **disappears at the cap**, with the configurable Settings editor (max count, length mode, wake-check toggle/delay) applying. The v3→v4 migration ran cleanly on the existing install.

## Wake-up check — merged on code-review + compile confidence; on-device verification PENDING

The wake-up-check native layer (Pigeon `scheduleWakeCheck`/`cancelWakeCheck`, `WakeCheckScheduler` + receivers + notification channel, Dart arming on real dismissal) is **code-complete, passed a careful native code review** (request-code namespaces traced; "I'm up" confirmed to cancel the exact re-fire; the re-fire arms before the permission-gated notification so the safety net always lands), and **compiles** (`flutter build apk --release`). It was merged **without a physical-device pass** at the user's request. It is inherently device-only-verifiable (AlarmManager/receivers/notifications), and it is **best-effort by construction** — a wake-check failure can never block dismissing an alarm (the final review's one regression, where a settings-load failure could make the ring screen unrenderable, was fixed in `6745e45`: `currentSettingsProvider` now falls back to defaults).

**Run this from `main` to confirm the wake-check on-device** (Settings → Wake-up check → "Check after" = 1 min to test fast):
1. Dismiss an alarm → ~1 min later a **"Still up?"** notification with an **"I'm up"** action appears.
2. Tap **"I'm up"** → no re-ring.
3. Ignore it ~100 s → the alarm **re-rings** (with its mission).
4. Toggle the feature off → a fresh dismissal schedules no check.
5. Deny notifications → still re-rung after the delay (no prompt) — honest degradation.

If any of 1–3 misbehave on device, it's a follow-up fix (best-effort native, no risk to the core alarm).

## Deferred minors (from the final whole-branch review)

- Reboot-during-a-future-snooze can re-ring the original occurrence slightly early (errs toward waking; dismissing clears `snoozedUntil`, no double-ring).
- A past `snoozedUntil` after reboot relies on the original scheduled time's recovery window (spec-accepted).
- The "Still up?" notification lingers after a re-fire (harmless); no reboot-persistence for a pending wake-check; `.toInt()` on the id bypasses the fail-loud guard (ids are small).
