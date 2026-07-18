# Rise Phase 5d — Push notifications + nudges (design)

**Date:** 2026-07-19
**Status:** Drafted (build-against-the-contract). Builds on 5a (auth), 5b (crew), 5c (status), 5e (leaderboard) — all merged.
**Builds on:** the merged social layer + a **Firebase/FCM project the user provides**. This is the first feature with a native push dependency.

## Goal

Let crew members **nudge** each other with a push notification — the core being "wake up, you're still asleep!" Requires: (a) the app registers its **FCM token** so the server can target it, (b) it **receives + displays** pushes, and (c) a **send-nudge** path (a Crew button → an edge function → FCM → the friend's device). Purely additive — nothing on the alarm/ring path changes, and the app degrades gracefully when unconfigured.

## Prerequisite the user provides (BLOCKS the build for the FCM parts)

Unlike Supabase (pure Dart config), Firebase Messaging needs native config at build time:
- **`android/app/google-services.json`** (from Firebase console → Add Android app, package `com.riseapp.rise`, debug SHA-1). Without it, `firebase_messaging` fails to compile. Gitignored.
- **A Firebase service-account key** (Firebase → Project Settings → Service accounts → Generate key) set as a **Supabase edge-function secret** (`FCM_SERVICE_ACCOUNT`), used server-side by the send-nudge function to call FCM HTTP v1. A real secret — never in the app/repo.

Tasks split into **Firebase-independent** (buildable now: nudge service/fake/providers/UI, the edge function, the SQL) and **Firebase-dependent** (need `google-services.json`: token registration + receive handler).

## Non-negotiable constraints (inherited)

- **Offline-first stays sacred.** No alarm/ring/snooze path touches FCM or the network. Nudging is best-effort and additive.
- **Degrades gracefully.** Unconfigured (no Supabase creds AND/OR no Firebase) → no token registration, `nudgeServiceProvider` → `DisabledNudgeService`, the nudge button is hidden. The local app is unchanged.
- `flutter_riverpod` 2.6.1; "Mono" tokens; injectable-service + fake pattern.

## Architecture

**FCM token registration** (`lib/data/push/push_registrar.dart`, Firebase-dependent): on sign-in (and token refresh), get the FCM token via `firebase_messaging` and upsert it to a `device_tokens` row `{user_id, token, platform, updated_at}` (own-row RLS). Remove on sign-out/delete. A `PushRegistrarHost` (or a hook in the auth flow) drives it. Best-effort; a failure never affects the app.

**Receiving** (`lib/data/push/push_receiver.dart`, Firebase-dependent): `FirebaseMessaging.onMessage` (foreground) shows a local heads-up (reuse a notification channel); `onMessageOpenedApp` / initial message routes into the Crew tab. Background/terminated pushes are shown by the system from the FCM `notification` payload. No custom background isolate needed for v1 (notification-only messages).

**`NudgeService`** (injectable, Firebase-INDEPENDENT) — `lib/data/nudge/nudge_service.dart`:
```dart
abstract interface class NudgeService {
  Future<void> nudge(String userId); // invoke the send-nudge edge function; best-effort
}
```
- `SupabaseNudgeService` — `supabase.functions.invoke('send-nudge', body: {'to': userId})`. **Build-verified.**
- `FakeNudgeService` — records the last nudged id + count (tests).
- `DisabledNudgeService` — no-op.
Provider: `nudgeServiceProvider` (Supabase when configured else Disabled).

## Data model (Supabase) — `supabase/migrations/0005_push.sql`

- `device_tokens(id uuid pk default gen_random_uuid(), user_id uuid → auth.users cascade, token text not null, platform text not null default 'android', updated_at timestamptz default now(), unique(user_id, token))`. RLS: own-row rw only (`user_id = auth.uid()`); no cross-user read (the send-nudge function reads via service role).
- `nudges(id uuid pk default gen_random_uuid(), from_user uuid → auth.users cascade, to_user uuid → auth.users cascade, created_at timestamptz default now())` — a log used for **rate-limiting**. RLS: insert/select where you are `from_user` (the edge function writes via service role after its own check).
- **`send-nudge` edge function** (`supabase/functions/send-nudge/index.ts`): authenticates the caller; verifies an **accepted friendship** between caller and `to`; **rate-limits** (reject if the caller nudged this target within the last N minutes, via the `nudges` log); reads the target's `device_tokens`; mints an FCM HTTP v1 access token from `FCM_SERVICE_ACCOUNT`; sends a push (`title: 'Rise', body: '@<caller> is nudging you to wake up 👋'`, data: `{type: 'nudge'}`); logs the nudge. All server-side; the service account never leaves the function.

## UI

- **Crew tab** (`crew_screen.dart`): each **friend** row (accepted only, not requests/pending) gets a small **"Nudge"** action (a bell/👋). Tapping calls `nudge(member.id)`; a brief per-member cooldown (disable + "Nudged") gives feedback and discourages spam. Errors → a SnackBar. Hidden when unconfigured/signed-out (the Crew tab already gates on signed-in).
- Incoming nudges appear as system notifications (from FCM); tapping opens the Crew tab.

## Error handling

- `nudge` failure (rate-limited, offline, not-crew) → a SnackBar; never affects the alarm.
- Token registration failure → swallowed; nudges just won't reach that device.
- All push code is outside any alarm path.

## Testing strategy

- **Nudge service (fake):** `nudge` records; disabled is a no-op.
- **Providers:** `nudgeServiceProvider` config-gated.
- **UI (widget):** the Nudge action calls `nudge(id)` for a friend; cooldown disables it; not shown for pending/incoming rows.
- **Edge function + FCM + token registration:** **review-verified + device-verified** (no live FCM in CI). The setup guide has a two-device nudge smoke test.
- **`firebase_messaging` init:** the app still builds/runs once `google-services.json` is present (build-verified with the file).

## Deliverables the user applies

`docs/superpowers/social/2026-07-19-supabase-firebase-setup-5d.md`: create the Firebase project + Android app (`google-services.json`); generate the service-account key; `supabase secrets set FCM_SERVICE_ACCOUNT=@key.json`; apply `0005_push.sql`; deploy `send-nudge`; a two-device nudge smoke test.

## Out of scope (5d)

Alarm-gifts (send a specific alarm/sound), voice-clips, "social escalation" auto-nudges when a friend sleeps through (a scheduled/triggered variant — later), iOS push (APNs — with the iOS engine), rich notification actions, nudge history UI.
