# Plan 1 — Android Reliability Protocol Results

**Date:** 2026-07-16
**Build:** app-release.apk (main + reboot-recovery fix)
**Gate (spec §9):** ≥99.5% ring delivery on should-ring scenarios.

---

## Device A: Samsung Galaxy S24 Ultra (SM-S928B)

- Android **16** (API 36), One UI **8.0**
- Manufacturer: **samsung** — the OEM-killer class the protocol most needs.
- Timezone at test: **Asia/Baku (UTC+4)** — a real non-UTC device.
- Battery: on charger throughout (relevant to the Doze result below).
- Ring UI note: the dev scaffold's "Ring in N minute(s)" arms for the top of the target minute (hour:minute granularity).

### Results (battery-optimization exemption granted — the Setup Guardian's "Fix")

| # | Scenario | How applied | Expected | Result | Evidence |
|---|----------|-------------|----------|--------|----------|
| 1+5 | **Screen locked + ringer silent** | Ringer mode 0 (silent), screen locked, wait | Rings audibly | ✅ **PASS** | `AlarmReceiver: alarm 2 fired` → `AlarmService: ringing alarm 2`; audio on alarm stream (`Standby: no`); **user confirmed audibly ringing** |
| — | **Timezone correctness** | Device zone Asia/Baku (UTC+4) | Arms at correct local instant | ✅ **PASS** | Armed `2026-07-17 12:14:00.000+0400` — the `+0400` offset proves `tz.local` resolves the device zone (pre-fix this rendered `Z`/UTC) |
| — | **Setup Guardian accuracy** | Fresh install, then "Fix" battery | Reports real gaps | ✅ **PASS** | On install: 3 green + **Battery unrestricted flagged red** (Samsung defaults to optimized). After Fix: all 4 green |
| 12 | **Reboot — alarm re-arming** | `adb reboot`, do NOT open app | Alarms silently re-armed | ✅ **PASS** | `BootReceiver: received BOOT_COMPLETED; re-running reconcile` → `AlarmScheduler: scheduled alarm N` — **without the app being opened** (headless engine) |
| 12b | **Reboot — missed-alarm recovery** | Alarm due ~8 s out, reboot immediately so it's missed during boot | Rings on boot via recovery | ⚠️→✅ **FAIL then FIXED** | See "Bug found and fixed" below. After fix: full chain `Recovering missed alarm 1` → `ringNow armed immediate alarm 1` → `AlarmReceiver: alarm 1 fired` → `AlarmService: ringing alarm 1`, audio playing, **verified on this device** |
| — | **Dismiss stops the alarm** | Tap Dismiss / force-stop | Alarm silences, service dies | ✅ **PASS** | `AlarmService: stopping alarm N`; service count → 0; notification cleared (also verified on emulator) |
| 10 | **Doze (deep idle)** | `dumpsys deviceidle force-idle` | Rings through Doze | ⚪ **INCONCLUSIVE** | Device on charger → `Unable to go deep idle; stopped at INACTIVE`. Doze requires the device unplugged; the alarm rang but not from true deep Doze. **Re-run unplugged.** |

**Delivery on should-ring scenarios exercised: 5/5 rang** (locked+silent, reboot re-arm, reboot recovery [post-fix], dismiss, timezone). Doze inconclusive (charger); the multi-day and special-condition scenarios below are not yet run.

---

## Bug found and fixed on-device: missed-alarm recovery silently failed on reboot

**The user's reboot test surfaced this — no unit test, task review, or whole-branch review caught it, though the whole-branch review *predicted* it and it had been deferred to Plan 2.**

- **Symptom:** set an alarm ~8 s out, reboot so it comes due during boot. On boot, `flutter: Recovering missed alarm 1` logged — recovery *detected* the miss — but **nothing rang.**
- **Root cause:** `AlarmHostApiImpl.ringNow` started the foreground service directly (`startForegroundService`). Recovery runs in the **headless boot engine**, a background context. Android 14+/Samsung block starting an FGS from the background — the same logcat showed `ForegroundServiceStartNotAllowedException` thrown at Samsung Health and WhatsApp at that moment. Rise's `ringNow` was silently blocked; the exception propagated into the engine's `finally` and was swallowed.
- **Fix (`AlarmScheduler.ringNow`):** instead of a direct FGS start, arm an immediate `setAlarmClock` ~1.5 s out with a dedicated request code (so it never disturbs the alarm's own future PendingIntent). The ring then flows through `AlarmReceiver` → foreground service — the **exact-alarm-broadcast path**, which is exempted and is the same path every normal alarm already uses. Scheduling an alarm is allowed from the background; only the direct FGS start was not.
- **Verified:** re-ran the identical reboot-recovery scenario on the same S24. Full chain fired and the alarm rang audibly. This is exactly the "when the OS fails, catch it" promise — and it was silently broken before.

---

## Not yet run — require conditions/time not available this session

- **#20 — 3-day idle (Samsung app sleep):** the single most important Samsung scenario. Needs ~3 days of real elapsed time with the app unopened, run once with and once without the battery exemption. Must be a multi-day soak.
- **#10 — Doze:** re-run with the device **unplugged** so deep idle can engage.
- **#3 — force-stop survival:** attempted; harness taps missed the button and it was not cleanly measured. Re-run: set alarm, `am force-stop`, confirm it still rings (on Samsung this is the exemption's real test).
- **#14 — missed beyond 30 min:** device off > 30 min; should NOT ring.
- **#18 — low battery (<15%):** requires draining.
- **#19 — during a phone call:** requires a real inbound call.

---

## Verdict

**Core engine verified on real Samsung hardware:** rings on a locked, silent phone; arms at the correct instant in a non-UTC zone; re-arms after reboot without the app; recovers a missed alarm on boot (after the fix); and Dismiss reliably stops it. The Setup Guardian accurately flags the one Samsung setting that matters.

**Not yet a launch pass:** the 3-day Samsung soak (#20) — the headline OEM-killer scenario — and the unplugged-Doze, force-stop-survival, and special-condition scenarios remain. Launch gate stays open on those.
