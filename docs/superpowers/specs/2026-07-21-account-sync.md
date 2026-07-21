# Account Sync / Backup — design

**Problem:** Alarms + streak/wake-history are local-only. A reinstall or new device loses them (the user hit this). Fix: back them up to the signed-in account and restore on a fresh device. **Offline-first stays the rule** — local Drift is the source of truth; the cloud is a backup + restore path, not a live authority.

**Scope (v1 = backup + restore, NOT live multi-device merge):**
- While signed in, push local alarms + wake-history to the account (debounced) so there's always a current backup.
- On sign-in on a device whose local alarms are **empty** (fresh install / post-wipe), auto-restore from the cloud backup.
- A manual "Restore from account" action in Settings for the edge cases.
- Graceful-degrade: does nothing when auth/Supabase unconfigured or signed out. No behavior change when off.

**Why backup-blob, not per-row sync:** alarm counts are tiny; a single JSON payload per user avoids the local-autoincrement-id ↔ global-id mapping problem and keeps conflict logic trivial. Restore-only-when-local-empty means no duplicate-merge headache in v1.

## Backend — migration `0008_account_backups.sql` (user applies)
- Table `account_backups (user_id uuid primary key references auth.users on delete cascade, payload jsonb not null, updated_at timestamptz not null default now())`.
- RLS: enable; a user may `select / insert / update / delete` only their own row (`user_id = auth.uid()`), all four policies explicit. No functions/triggers needed (single-owner row). Match the 0006/0007 comment style.
- `payload` shape: `{ "v": 1, "alarms": [ {hour,minute,days,enabled,label,soundAsset,vibrate,mission,missionDiff,missionCount,missionData} ], "wakeEvents": [ {alarmId,scheduledAt,firstRingAt,dismissedAt,method,snoozeCount,missionFailures,onTime,label,alertnessScore} ] }`. Exclude device-local runtime fields (alarm `lastDismissedAt`/`snoozedUntil`; wake-event `id`). Store timestamps ISO-8601 UTC.

## Client
- `BackupService` (behind an interface + fake, like the other services):
  - `Future<void> push()` — serialize local alarms + wake_events → `upsert` the row. Best-effort; swallow errors (never block the UI). Debounced by the caller.
  - `Future<bool> restore()` — fetch the row; if present, write alarms + wake_events into local Drift **only when the local alarms table is empty** (fresh device); return whether it restored. Preserve local runtime fields (don't set lastDismissedAt/snoozedUntil). After inserting alarms, trigger a reconcile so they arm natively.
  - Graceful-degrade: no-op when `authServiceProvider is DisabledAuthService` or signed out.
- **Triggers:**
  - Auto-`push()` (debounced ~a few seconds, or on app-pause) after alarm mutations + wake-event finalize, while signed in. Wire into the existing alarm-mutation + wake-recorder paths (a light listener/provider), not into every call site.
  - Auto-`restore()` once on sign-in when local alarms are empty.
  - Manual "Restore from account" row in Settings (confirm dialog; calls `restore()` and toasts the result).
- Providers follow the existing injectable-service + riverpod 2.6.1 pattern; gate on configured+signed-in.

## Tests
- Pure serialization round-trip (alarms + wake_events → JSON → back) unit-tested.
- `restore()` only-when-empty logic tested with a fake backend + in-memory Drift.
- Suite stays green; `flutter analyze` clean. Build-verified; deploy nothing.

## Device validation (after)
- Sign in → add an alarm → confirm a backup row appears (or is upserted). Reinstall / clear data → sign in → alarms + streak restore. Confirm signed-out / unconfigured does nothing.
