# Rise — accurate status (2026-07-21)

Single source of truth for "what's done vs. what's left." Supersedes rough counts. See `build-log-2026-07-20.md` for the per-commit detail and `roadmap-2026-07-20-master.md` for the phase plan.

## ✅ Done + DEVICE-VERIFIED (on Galaxy S24 Ultra, Android 16)
- **Core alarm** — fires through a **locked screen** at the exact time, full-screen ring (the "wake up 100%" claim). Uses the Doze-exempt `setAlarmClock()`.
- **Reliability / Setup Guardian** — Notifications / Exact-alarm / Full-screen checks all green on device.
- **Alertness Engine (PVT, Phase 6)** — mission ran end-to-end, dismissed, streak advanced, score persisted + shown in Stats.
- **Drift migrations → v8** — an existing install upgraded with data preserved.
- **Login/auth (Phase 5a)** — Google sign-in working on device (config baked in; SHA-1 registered).
- App launches, Mono theme, all 4 tabs; Stats / Profile / Create-Edit all render with the new features.

## ✅ Done, build-verified (analyze-clean + tests), NOT yet fully device / 2-account tested
- Phase 7 Compassion, 8 Rhythm & Care (PHQ-2), 9 Missions (PVT device-tested; **QR/shake/steps not yet**), 10 Sensory (sunrise/light), 11 Wake-confidence (opt-in), 13 Stats/achievements, 14 Crew depth, 15 Groups, 16 Voice, 17 Monetization (unlocked till RevenueCat wired), 18 icon + l10n scaffolding.

## 🔧 In progress NOW (from 2026-07-21 device testing feedback)
- **UX cluster** (`fix-ux-onboarding-signout`): sign-out confirm+loader+feedback · branded in-app toast system · onboarding built-in sign-in step + polished login.
- **NEXT — Account sync/backup**: alarms + streak/wake-history sync to the account so a reinstall/new device restores them (offline-first kept). New migration you'll apply.

## ⏳ Deferred — need device / Mac / your accounts / assets (build WITH you, not blind)
- **Voice-as-alarm** — a received friend's clip plays as your wake sound (native ring-audio; user requested — do next after sync).
- **Missions:** photo-match + PERCLOS/camera-eye (ML Kit — heaviest native).
- **Sensory:** real CC0 sound *files* (you supply), native volume fade-in, per-alarm vibration patterns.
- **Phase 18 rest:** dark mode (visual refactor), home-screen widget, HealthKit/Fit, full l10n string migration, a11y audit, Philips Hue.
- **Phase 8:** bedtime reminders (notification scheduling).
- **Backend social extras:** group challenges, activity feed, reactions, server streak-break fan-out, custom push copy, deep-link invites.
- **Phase 11:** native "cancel wake-check" so smart-wake can become default.
- **iOS:** the whole Mac compile pass (`reliability/2026-07-20-ios-compile-checklist.md`) + on-device iOS test.
- **Launch (Phase 19):** name/trademark, ASO, TikTok kit, store listings, release keystore + its SHA-1, reliability soak.

## Backend you still need to apply
- Migrations `0006_groups.sql`, `0007_voice_clips.sql` (+ the upcoming sync migration). Create the private `voice-clips` Storage bucket. Wire RevenueCat for the paywall.
