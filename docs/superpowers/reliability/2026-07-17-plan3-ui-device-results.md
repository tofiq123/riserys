# Plan 3 (alarm-core UI) — on-device verification results

**Date:** 2026-07-17
**Device:** Samsung Galaxy S24 Ultra (SM S928B), Android 16 (API 36)
**Build:** `plan3-screens` HEAD `5b0271e`, release APK (`flutter build apk --release`).

## Outcome: PASS — verified by the user

The full Plan 3 UI ran on the physical device and the alarm-core flow works end to end. The user confirmed the checklist passes, including the two hardware-only behaviors that can't be verified from the Windows dev machine:

- **Rings through silent + locked with a mission gate** — a missioned alarm fired through silent mode on a locked screen, showed the ring screen, and could only be dismissed by completing the mission (no half-asleep swipe-out).
- **Reboot re-arm** — an alarm set before a reboot still rang after the device restarted without opening the app (boot re-arm + missed-alarm recovery from Plan 1 remain intact under the new UI).

Also exercised: onboarding → permissions grants → Alarms tab; onboarding skipped on relaunch (flag persisted); create/edit/toggle/delete; alarm preview; the Profile reliability permissions.

## Install note (process learning)

`flutter install --release` re-pushed a **stale** `app-release.apk` (dated 2026-07-16, pre-UI) instead of rebuilding — it completed in ~5s with no Gradle run, so the device first showed the old dev scaffolding UI. Fix: always `flutter build apk --release` (force a fresh compile) before installing, or `adb install -r` the freshly-built APK. Verified the fresh build shows onboarding + the tab bar.

## Follow-ups (not blocking merge)

- Deferred cosmetic minors from the final review (token literals, reduced-motion pulse, fire-and-forget settings write) — see `.superpowers/sdd/progress.md`.
- A custom launcher icon (currently the default Flutter icon).
- The longer Plan 1 Task 13 soak (multi-day Doze / force-stop survival) still pending.
