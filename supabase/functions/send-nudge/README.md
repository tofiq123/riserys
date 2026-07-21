# send-nudge

One edge function, four typed crew pushes. The client POSTs
`{ "to": "<uuid>", "kind": "nudge" | "voice" | "backup" | "sos" }`
(`kind` optional, defaults to `nudge` for pre-typed clients) with the user's
JWT; the function verifies, rate-limits, and pushes via FCM HTTP v1.

## Security model

- **Copy is 100% server-controlled.** The client contributes only the target
  uuid and an allowlisted `kind`; title/body come from the `COPY` map in
  `index.ts`. Any other `kind` → 400. Never add a free-text message param —
  that is a push-injection vector.
- The one dynamic fragment is the **sender's** username, read server-side
  from `profiles` (never from the request).
- Unchanged from before: JWT auth required, `to` must be a UUID (it is
  spliced into a PostgREST filter), accepted-friendship gate, fail-closed
  rate limiting, stale FCM tokens pruned on 404.

## Kinds and copy

| kind     | title                    | body                                                  |
| -------- | ------------------------ | ----------------------------------------------------- |
| `nudge`  | Wake-up nudge 👋         | `@ada` is nudging you awake.                          |
| `voice`  | New voice clip 🎙️        | `@ada` sent you a wake-up clip — open Rise to listen. |
| `backup` | Crew update 💪           | `@ada` slipped today and is back on it — cheer them on. |
| `sos`    | `@ada` can't wake up 🚨  | They asked the crew for backup — give them a shout.   |

The FCM data payload carries `{ type: <kind>, kind: <kind> }` so the app can
route on it.

## Rate limiting

The `nudges` table (migration 0005) has no kind column and we deliberately
did not add one — so v1 is **one shared per-pair 5-minute bucket** for every
kind, computed from that log and only consumed after a real delivery.

Exception: `voice` may bypass the bucket **only** when a `voice_clips` row
from caller→target was created in the last 2 minutes. That row is server
truth (RLS-gated insert + a real audio upload), not a client claim, so the
bypass can't be farmed for spam. Both the bucket query and the bypass query
fail **closed**.

## Deploy

Controller-run (no CLI in agent worktrees):

```
supabase functions deploy send-nudge --project-ref gnhaqkkwjkzkftnrojom
```

No new secrets, no migration — `FCM_SERVICE_ACCOUNT` and 0005/0007 are
already in place.
