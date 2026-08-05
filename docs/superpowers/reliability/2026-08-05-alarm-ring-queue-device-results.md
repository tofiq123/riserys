# Overlapping-alarms ring queue — verification results

**Date:** 2026-08-05
**Device:** Samsung Galaxy S24 Ultra (SM-S928B), Android 16 (API 36)
**Build:** debug APK, `--dart-define-from-file=rise.env.json`, `adb install -r`

## Ring queue — device-verified PASS

Two alarms a few minutes apart, each with its own label and at least one with
a mission:

- **No clobbering:** with the first alarm ringing, once the second alarm's
  scheduled time passed, the first alarm's audio and vibration did not glitch,
  stop, or restart. The ring screen showed the new **"Next: `<label>` queued"**
  line.
- **Dismiss advances the queue:** dismissing the first alarm started the
  second ringing immediately afterward, with its own sound/vibration/mission
  and no chip (nothing queued behind it).
- **Snooze advances the queue too:** snoozing the first alarm (instead of
  dismissing) also started the second ringing immediately — it did not wait
  out the first alarm's snooze window.

User confirmed all of the above, having run the full two-scenario script from
the implementation plan
(`docs/superpowers/plans/2026-08-05-alarm-ring-queue.md`, Task 3).

## Unrelated issue found during this pass

While testing, snoozing an alarm and then editing its scheduled time produced
an incorrect "next ring" time on-screen and in the notification — it did not
consistently reflect the edit against the active snooze. This is a pre-existing
bug in the snooze/edit/reconcile interaction, not caused by or related to the
ring queue change in this branch. Tracked separately; see the next entry in
`docs/superpowers/reliability/` once investigated.
