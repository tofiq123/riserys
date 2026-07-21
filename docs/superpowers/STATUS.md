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

## ✅ Done 2026-07-21 (from device-testing feedback) — on `main`, 807 tests
- **Sign-out fix** (`fc68ae9`) — confirmation dialog + loading spinner + "Signed out." feedback (no more silent multi-tap).
- **Onboarding sign-in step** (`c116482`) — a final "Sign in with Google / Continue as guest" page (only when auth configured); + **polished login card** (`52c84f2`).
- **Account sync/backup** (merge `2c1a793`) — per-account cloud backup of alarms + wake-history; auto-push (debounced) while signed in, auto-restore on sign-in to an **empty** device, manual "Restore from account" in Settings. Offline-first kept. **Migration `0008_account_backups.sql` — you apply.** RLS reviewed (single-owner row, airtight).
  - **Device-validate:** apply 0008 → sign in → add alarm → backup upserts; reinstall/clear → sign in → alarms+streak restore; signed-out/unconfigured does nothing.
- **In-app toasts:** existing `toast.dart` (dark pill) kept; sign-out/success use it. A broader "make every toast beautiful" polish pass is still open (minor).

## 🔧 Still open from the 2026-07-21 feedback
- **Voice-as-alarm** — a received friend's clip plays as the wake sound (native ring-audio; do next).
- **In-app toast polish** — unify all snackbars onto the branded toast with success/error/info variants (minor).

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
