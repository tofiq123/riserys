# Round 3 — Crew, Stats, Group and Friend: structural redesign

**Status:** approved 2026-07-26 from the interactive mockups
(artifact `4dc1b5c2-009c-4f0d-afab-8b1f020f523a`).
**Supersedes the bodies of:** `2026-07-26-social-ux-overhaul-design.md`,
`2026-07-26-bold-redesign-addendum.md`. Their *state* invariants still hold.

## Why

Rounds 1 and 2 changed states and top cards; the screen bodies were untouched, so
neither read as a redesign. Seven findings from walking the four screens in the
states users actually land in:

1. Stats is twelve sections of identical visual weight in one flat scroll.
2. Five unrelated scores (streak, on-time %, consistency, alertness, crew score)
   never appear together, so none can be compared.
3. Crew is time-blind — identical at 06:05 and 22:40, though the product is about
   one moment in the day.
4. Crew lists the same people twice: the status strip and the feed.
5. The week chart plots "minutes late", which cannot answer *when do I get up?*
6. Groups are a 116 px strip below the fold, and the group page opens on an invite
   code rather than on the group.
7. Empty and signed-out — the front door — are a card with a button.

All seven are structure, not styling. This round changes the bodies.

## Scope

In: `crew_screen`, `stats_screen`, `group_detail_screen`, `friend_detail_screen`,
`groups_tab`, plus new shared components and two new pure-domain modules.
Out: the alarm path, auth, providers/caching, backend, migrations, packages.

## 1 — Crew: the Morning Line

One vertical time axis with a live marker at the current minute.

- **Above the marker:** everyone who has woken today, ascending by wake time.
  Each row: time (mono, tabular) · outcome mark · avatar · name · verdict
  ("on time" / "+5 late") · streak · reaction tally + one **Cheer** affordance.
- **The marker:** current time, amber, a breathing ring on the dot only.
- **Below the marker:** everyone not yet up, by status rank — *waking now*
  (amber ring, Cheer promoted), *asleep*, *quiet*. Not time-positioned: friends'
  next-alarm time is not published (decision 3 below).

This replaces both the This-morning chip strip and the "Cheer them on" feed. The
full Activity screen stays, reached from "see all".

### Phases

`MorningPhase` is derived, in this order:

| # | Rule | Phase |
|---|------|-------|
| 1 | local hour ≥ 21 or < 4 | `tonight` |
| 2 | any crew status is `waking` | `window` |
| 3 | a wake landed today and `now − lastWake ≤ 3 h` | `window` |
| 4 | local hour < 10 | `window` |
| 5 | otherwise | `wrapped` |

- **window** — amber wash on the hero, live count "3 of 6 up", pip per member,
  first-up line, NOW marker present.
- **wrapped** — neutral hero, "WRAPPED · WINDOW CLOSED hh:mm", no marker; people
  who never woke appear at the bottom with a dash and "no wake logged".
- **tonight** — indigo wash, your own next alarm as the headline with a countdown,
  its group/mission/sound, then how many of the crew already have an alarm set,
  and a collapsed recap of yesterday's line.

### Copy rules

State the fact ("3 of 6 up"), never a mood. A missed morning is a dash and
"no wake logged" — never red, never an exclamation. The button says **Cheer**;
the toast says **Cheered**.

## 2 — Stats: one summary, three lenses

### Summary block (always visible, inverse ground)

Current run in 52 px mono + the last 7 mornings as outcome marks; one sentence
("On time 6 of 7 this week."); a Week / Month / Year period control with the lock
glyph on the premium periods; then four figures on one row with their change on
the previous period: **on time %**, **avg wake**, **best run**, **consistency**.
Below ~340 pt the four reflow to a 2×2 rather than truncating.

### Lenses (`SegmentedControl`, existing component)

- **Rhythm** — the wake-time chart, the 35-day grid, patterns. Default.
- **Progress** — streak-at-risk banner, streak detail + run sparkline,
  achievements as a horizontal medallion rail, alertness score + trend +
  disclaimer, then Rough night / Share.
- **Crew** — podium for the top three, compact rows below with your own row
  highlighted wherever it falls, crew score.

Nothing is deleted. Mapping: wake-evidence card → top of Rhythm; accountability
ping → the Progress risk banner; overview period toggle → the summary control;
week chart + calendar → Rhythm; consistency → a summary figure plus Rhythm's
footer line; alertness + trend + disclaimer → Progress; patterns → Rhythm;
achievements → the Progress rail; leaderboard + crew score → Crew.

### The wake-time chart

Y axis is clock time. Per day: a **target ribbon** from `firstRingAt` to
`firstRingAt + 15 min` — this is literally the on-time rule
(`WakeEventRepository.grace`), so a dot inside the ribbon is on time *by
construction* and position can never disagree with the mark. The ribbon steps
when the alarm moves, which shows weekend drift for free. One mark per morning at
`dismissedAt`; a hairline connects them; only the latest morning and the extreme
are labelled.

## 3 — The mark vocabulary (accessibility-critical)

Verified with the dataviz validator against the shipped palette:

- light ground: on-time `#16A34A` vs slept-through `#DC2626` → **ΔE 5.0
  (deuteranopia)**; amber vs green → 5.7.
- dark ground: **ΔE 7.9**, inside the 6–8 floor band.

Both are at or below the floor where colour alone can separate two marks, so
**colour must never be the only encoding.** One shared vocabulary, used by the
chart, the grid, the Morning Line rail, the hero's 7-morning dots and the legend:

| Outcome | Mark | Colour |
|---|---|---|
| On time | filled dot / filled square | `positive` |
| Late | hollow ring, 2.2 px stroke | `text` — neutral, never red |
| Slept through | cross | `danger` |
| Rest day (excused) | horizontal dash | `textFaint` |
| Freeze absorbed | ring + centre pip | `asleep` |
| No alarm | 2 px dot on the baseline | `border` |

A legend is always present and always labelled. The chart carries a **Show as a
list** toggle giving the same data as exact times. Do not drop the shapes and
keep the colours.

## 4 — Group: the group's morning first

Order becomes: nav (name + member count + your role) → the group's morning (count,
status-ringed faces) → streak race as a first-class banner with the owner's
control on it → podium → compact standings with the race chip → group score →
invite → leave/delete. Invite moves from first to second-to-last: it is needed
once. A group of one renders as a share screen, not an empty leaderboard.

## 5 — Friend: today, then the actions, then their rhythm

Identity with status ring → **Today** card (woke at, on time, run, what your crew
already left) with **Cheer / Nudge / Voice** on the same card → their 14-day
rhythm chart with a plain sentence → You two (head-to-head + line) → shared groups
→ "in your crew since". When they are mid-mission the Today card becomes a live
amber card with Cheer promoted; with no data it says what will appear and when,
and still offers the actions.

## 6 — Motion

| What | Spec |
|---|---|
| Section entrance | 12 px rise + fade, 320 ms easeOutCubic, 40 ms stagger (existing `CrewEntrance`) |
| NOW marker | 2.4 s breathing ring on the dot only, inside a `RepaintBoundary` |
| Crossing the line | new wake slides from below the marker to its slot, 480 ms, with a 900 ms amber wash that decays |
| Lens switch | 180 ms crossfade + 8 px slide in the direction of travel |
| Chart entrance | ribbon first, then marks fade left→right 30 ms apart, 260 ms total |
| Numerals | count-up on first paint only, 650 ms (existing `_CountUp`) |
| Reaction | chip 1 → 1.18 → 1 over 220 ms, optimistic tally |
| Press | 0.975 / 110 ms (existing `RisePressable`) |

Every one resolves instantly to its end state under
`MediaQuery.disableAnimations`.

## 7 — Performance

- Stats moves to `CustomScrollView`; only the active lens is in the tree.
- Morning Line and standings become `SliverList.builder` — off-screen rows are
  not built.
- The chart and the grid are one `CustomPainter` each, not 14 and 35 widgets;
  `shouldRepaint` compares data identity only.
- One 30 s ticker on Crew, scoped so only the marker and the hero count rebuild.
  Nothing else reads `DateTime.now()` during build.
- Derived values (roster merge, standings sort, rhythm build) move behind
  providers with `select`.
- Provider caching, warmup and account keying are unchanged.

## 8 — States

Restoring · signed out · empty · first-run-no-data · loaded · refreshing ·
stale/offline · error-no-cache · partial failure · premium locked · long content ·
360×640 · reduced motion · dark. Rules per state are in the artifact's matrix; the
load-bearing ones:

- Skeletons carry the **loaded layout's exact geometry**, so nothing moves.
- Loading is never rendered as signed-out. `AsyncData(null)` means signed out;
  `AsyncLoading` means skeleton. (Invariant from `social-ux-overhaul` — keep.)
- Stale data stays on screen, dimmed, with when it was fetched and a retry.
- A section that fails carries its own retry; the rest of the screen keeps working.

## 9 — Decisions taken

1. **Timeline replaces the feed** on Crew. The Activity screen stays behind "see all".
2. **Three lenses** on Stats.
3. **No new backend.** Below the marker shows status only; next-alarm sharing is
   not built. If it is ever added, the line below NOW becomes time-positioned.
4. **No wind-down line.** It needs a sleep-goal setting; out of scope.

## 10 — Non-goals

No new colour tokens, no new typeface, no new package, no migration, no change to
the alarm path or to the four privacy invariants. The alertness disclaimer stays
on its card, unchanged: nothing here implies a medical reading.
