# Security hardening — follow-ups

A security & privacy audit (2026-07-22) confirmed **all four privacy invariants
hold in code**, found **no Critical/Important vulnerabilities**, and **no secrets
in the repo**. What follows are the remaining defense-in-depth items.

## Done — migration `0011_security_hardening.sql` + code

1. **voice_clips storage_path prefix** — an INSERT may only name an object under
   `<owner_id>/…`, closing a theoretical cross-user Storage read.
2. **feed_reactions emoji anti-text** — reactions can't carry alphanumeric free
   text (emoji/symbols only); the in-app feed's one client string is now bounded.
3. **account_backups payload size cap** (~1 MB) — stops self-row bloat.
4. **delete-account edge fn** — no longer forwards the raw admin error to the
   client (returns a generic message; logs detail server-side). **Redeploy:**
   `supabase functions deploy delete-account --project-ref <ref>`.

## Deferred — rate limiting (low priority pre-launch, implement thoughtfully)

These are all "at scale" abuse vectors with negligible payoff at the current
(pre-launch) user count. Each needs a per-caller counter (table + window) done
carefully to avoid locking out legitimate users — better done deliberately than
rushed. Prioritise before any real growth / public launch.

- **`find_user_by_username` (0002)** — unthrottled username→profile resolution
  enables directory harvesting of `{id, username, display_name, avatar_color}`.
  Fix: per-caller rate limit on the RPC, or don't return `id` until a request is
  actually sent.
- **`join_group_by_code` (0006)** — 6-char codes (~8.9e8 space), unthrottled;
  brute-forcing could auto-join strangers' groups (roster + group-shared stats
  visible; wake feed stays friends-only). Fix: per-caller rate limit; optionally
  lengthen codes to 8.
- **friend-request creation (0002)** — no cap on outgoing pending requests →
  request spam. Fix: per-requester windowed count limit via a trigger or edge
  path.

A shared pattern for all three: a `rate_events(actor uuid, action text, at
timestamptz)` table + a SECURITY DEFINER `check_rate(action, max, window)`
helper called at the top of each RPC, with periodic cleanup. Test the lockout
thresholds against real usage before enabling.
