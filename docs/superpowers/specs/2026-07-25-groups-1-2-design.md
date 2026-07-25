# Groups 1 & 2 — Design & Build Plan (2026-07-25)

Builds out the two backlogs surfaced earlier: **Group 1** (deferred engineering) and
**Group 2** (research-driven product features). User directive: build everything,
defer nothing, safest-first. Source backlogs: `STATUS.md` (Deferred) and
`memory/research-synthesis.md` (novel ideas + red lines).

## Locked decisions
- **Order:** Group 1 fully, then Group 2. Safest/smallest → largest.
- **Group challenge:** *Streak race* — crew members keep a wake streak alive; the
  challenge tracks who's still standing and who broke first.
- **Crew SOS:** *Manual + auto, opt-in.* User opts in to letting their crew be a
  backup; then a manual "wake me" escalation is always available AND it auto-fires
  on repeated slept-through / failed wake-check. Push text stays 100% server-composed.
- **PHQ-2:** *Yes* — optional, opt-in, with a "consider seeing a doctor" off-ramp,
  never gated behind streaks, never diagnostic.

## Red lines (cross-cutting guardrails — enforced in every Group 2 surface)
Never diagnose/treat or label a score "abnormal"; never claim sleep-stage / "smart"
waking; never imply the screen light wakes you biologically; never shame; never
auto-prescribe melatonin / light / sleep-restriction; only free/public-domain
instruments (PHQ-2 is free). Positioning disclaimer modeled on VA Insomnia Coach.
These are implemented as a reusable disclaimer/off-ramp component + copy rules, built
**first** in Group 2 so the screener and alertness features inherit them.

## Honest constraints (coded, not skipped — but only you/hardware can close)
1. **iOS notification headroom** — Swift written but **compile-unverified** (no Mac);
   folds into the iOS compile pass.
2. **Backend items** (rate-limits, challenges, SOS) — I author SQL migrations + RLS;
   **you apply them** to Supabase and review. No service-role keys/secrets touched.
3. **Cross-account behaviors** (SOS delivery, challenge sync) need a **2-device test**.

## Group 1 — build order
1. **Bottom-sheet scrim polish** — unify modal barrier colour + reduce-motion + a11y
   across all `showModalBottomSheet` call sites. Pure Flutter, widget-tested.
2. **SQL rate-limits** — username lookup, invite-code join, friend requests. New
   migration + RLS/policies per `docs/security-hardening-followups.md`.
3. **Crew SOS** — opt-in setting + manual escalation + auto-trigger on repeated
   slept-through, wired to the existing typed `backup` push. Widget/unit-tested.
4. **Group challenges (streak race)** — own design doc + nod before build: new
   table(s) + RLS + crew UI + sync.
5. **iOS notification headroom** — headroom logic in the iOS notification allocator;
   marked compile-unverified.

## Group 2 — build order
6. **Red-lines framework** — reusable disclaimer + "see a doctor" off-ramp component
   + copy rules. Leads Group 2 (constrains 7–8).
7. **Alertness Score / mini-PVT** — ~60–90s reaction-time wake mission + score,
   pure Flutter, no permissions. Extends the existing PVT signal in the wake card.
8. **PHQ-2 screener** — optional opt-in 2-question check-in + off-ramp.
9. **Wake-confidence engine** — own design doc + nod before build: fuse motion +
   app-events + PVT into post-dismissal confidence + graceful re-ring (extends the
   0–100 wake score + wake-check).
10. **Repositioning (Reliable·Verified·Kind·Together)** — woven through copy as each
    surface is touched.

## Working rules
- Each item: right-sized design → build → `flutter test` green → `flutter analyze`
  clean → commit. Large items (challenges, confidence engine) get their own spec +
  a design nod first.
- Feature branch `feat/groups-1-2`; merge coherent, green chunks to `main`.
- Security: RLS reviewed before any backend migration is proposed as done; no secrets
  committed; `google-services.json` / `rise.env.json` stay gitignored.
