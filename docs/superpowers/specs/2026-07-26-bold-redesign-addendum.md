# Bold redesign addendum — visible heroes on Crew / Stats / Profile

**Date:** 2026-07-26 (addendum to `2026-07-26-social-ux-overhaul-design.md`)
**Trigger:** user verdict on the first pass: "nothing changed in screens" — correct,
because that pass fixed states (flash/loaders/duplication) while deliberately
preserving at-rest layouts, and the states the user actually sees on a fresh
install (signed-out, empty) were left untouched. User chose **Bold redesign**.

## Rule learned
Every redesign must be visibly different in the states the user actually lands
in first: signed-out, empty-data, just-installed. Empty states are the front
door, not an edge case.

## Design
One **dark morning-card hero per tab** (RiseColors.primary ground, `lg` radius,
generous padding) carrying that tab's headline stat; amber (`RiseColors.waking`)
only as eyebrow/accent — the Riserys brand accent finally on the surfaces. All
other cards stay light and quiet. New shared component `HeroCard`
(`lib/ui/components/hero_card.dart`) + an on-dark `HeroButton`.

- **Crew signed-out (configured):** dark hero — eyebrow YOUR CREW, display
  "Wake up together", warm body, light-filled Google button on the dark card.
  Unconfigured: same hero, "Accounts are coming soon to this build." caption
  instead of a dead button (rule unchanged).
- **Crew signed-in, has crew:** dark hero — eyebrow THIS MORNING, live count
  line ("2 of 4 up" in mono; "All quiet — be the first up." when none), the
  status-ringed avatar chips INSIDE the dark card (`CrewMemberChip.onDark`).
  Replaces the flat "This morning" section label + strip.
- **Crew signed-in, no crew yet:** same dark hero with "Mornings are better
  with a crew" + Add your first friend (light button) + Join a group (ghost).
- **Stats, any state:** dark streak hero — eyebrow CURRENT STREAK, the number
  in 56px mono with amber flame, Best · Freezes row, and a 7-day outcome dot
  strip inside the hero. Empty data shows the same hero with 0 and "Set an
  alarm — your streak starts on the first on-time morning." (replaces the grey
  "No wake data yet" card so even an empty Stats reads as new).
- **Profile signed-in:** identity header instead of a card row — centered
  avatar disc (72), display name, @handle in mono, then the grouped cards.
- **Profile signed-out (configured):** dark hero "Make it yours" + light
  Google button. Guest (unconfigured) card unchanged.

Copy strings that tests key on are kept where the meaning is unchanged
("Wake up together", "Sign in with Google", "Mornings are better with a crew");
the Stats empty-state copy changes and its test updates with it.

Out of scope: Home/Alarms (user: fine), Settings, group detail (already
rebuilt this morning — visible once a group is opened), design tokens.
