# Round 3 Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: use superpowers:executing-plans to
> implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Rebuild the bodies of Crew, Stats, Group and Friend around a live
Morning Line and a one-summary-plus-three-lenses Stats, per
`docs/superpowers/specs/2026-07-26-round3-redesign-design.md`.

**Architecture:** Two new pure-domain modules (`morning_line.dart`,
`wake_rhythm.dart`) carry every derivation, so all the new logic is unit-testable
without a widget tree. One shared mark vocabulary (`outcome_mark.dart`) is used by
both `CustomPainter`s, the timeline rail and the legends, so the accessibility
contract cannot drift between surfaces. Screens become thin composition over those
pieces; Stats splits into a shell plus three lens files.

**Tech Stack:** Flutter 3.35.1, Riverpod 2.6.1 (pinned), Drift, existing
`RiseColors` / `RiseText` tokens. No new packages.

## Global Constraints

- No new colour tokens, typefaces, packages, migrations, or backend calls.
- Riverpod stays pinned at 2.6.1; social providers stay non-`autoDispose` and
  keyed to `accountProvider.select((a) => a.value?.id)`.
- Loading is never rendered as signed-out: `AsyncLoading` → skeleton,
  `AsyncData(null)` → signed out.
- Supabase stream services keep withholding their placeholder until first load.
- Outcome is encoded as **shape first**; colour only ever repeats it. Legends are
  always present and labelled.
- Every animation resolves instantly under `MediaQuery.disableAnimations`.
- On-time grace is `WakeEventRepository.grace` (15 min) — never a literal.
- Never bulk-edit Dart with PowerShell `Get/Set-Content` (corrupts non-ASCII).
- Device builds: `flutter build apk --dart-define-from-file=rise.env.json`.
- Verification gate for every task: `flutter analyze` clean **and**
  `flutter test` green.

---

### Task 1: Streak exposes which misses a freeze absorbed

**Files:** Modify `lib/domain/streak.dart` · Test `test/domain/streak_test.dart`

**Produces:** `StreakStats.freezeAbsorbed` — `Set<DateTime>` of local-midnight
days where a miss consumed a freeze instead of breaking the run. Defaults to
`const {}` so every existing construction still compiles.

- [ ] Add `final Set<DateTime> freezeAbsorbed;` with `this.freezeAbsorbed = const {}`
      in the constructor and `freezeAbsorbed: <DateTime>{}` in `empty`.
- [ ] In the fold's `DayOutcome.miss` arm, when a freeze is consumed, add that day
      to a local set; pass it to the returned `StreakStats`.
- [ ] Test: `freezeAbsorbed names the day a freeze covered` — 7 successes (earns a
      freeze), then a miss, then a success; assert `current == 8`,
      `freezeAbsorbed` contains exactly the miss day.
- [ ] Test: `a break with no freeze leaves freezeAbsorbed empty`.
- [ ] Commit: `feat(domain): streak reports which misses a freeze absorbed`

---

### Task 2: `wake_rhythm.dart` — the chart's data

**Files:** Create `lib/domain/wake_rhythm.dart` · Test `test/domain/wake_rhythm_test.dart`

**Consumes:** `WakeEvent`, `StreakStats.freezeAbsorbed` (Task 1).

**Produces:**

```dart
enum RhythmOutcome { onTime, late, sleptThrough, restDay, noAlarm }

class RhythmDay {
  const RhythmDay({required this.day, required this.outcome,
      this.ringMinute, this.wokeMinute, this.graceMinutes = 15});
  final DateTime day;        // local midnight
  final int? ringMinute;     // firstRingAt as minutes after local midnight
  final int? wokeMinute;     // dismissedAt as minutes after local midnight
  final RhythmOutcome outcome;
  final int graceMinutes;
  int? get graceEndMinute;   // ringMinute + graceMinutes, or null
  bool get hasAlarm;         // ringMinute != null
}

List<RhythmDay> buildRhythm(List<WakeEvent> events, DateTime now, {
  int days = 14,
  Set<DateTime> excusedDays = const {},
  Set<DateTime> freezeAbsorbed = const {},
});

({int lo, int hi}) rhythmRange(List<RhythmDay> days);   // padded, min 90-min span
String rhythmSummary(List<RhythmDay> days);             // "Up within 15 minutes of your alarm on 12 of 14 mornings."
({int onTime, int late, int slept, int rest, int none}) rhythmTally(List<RhythmDay> days);
```

Classification, first match wins: excused → `restDay`; no event → `noAlarm`;
`dismissedAt == null` and the day is past → `sleptThrough`; `onTime` → `onTime`;
else → `late`. `freezeAbsorbed` days keep their `late`/`sleptThrough` outcome —
the freeze pip is drawn on top by the mark layer, so the outcome stays truthful.

- [ ] Test: `returns exactly N local days, oldest first, ending today`
- [ ] Test: `classifies on time, late, slept through, rest day and no alarm`
- [ ] Test: `picks the on-time event when a day has several`
- [ ] Test: `rhythmRange pads the extremes and never spans less than 90 minutes`
- [ ] Test: `rhythmRange survives a day with no wakes at all`
- [ ] Test: `rhythmSummary counts only days that had an alarm`
- [ ] Commit: `feat(domain): wake rhythm — per-morning outcomes against the on-time window`

---

### Task 3: `morning_line.dart` — the Crew timeline's data

**Files:** Create `lib/domain/morning_line.dart` · Test `test/domain/morning_line_test.dart`

**Consumes:** `CrewMember`, `CrewStatus`, `FeedItem`, `crewStatusStyle` rank.

**Produces:**

```dart
enum MorningPhase { window, wrapped, tonight }

MorningPhase phaseFor({required DateTime now, required List<DateTime> todayWakes,
    required Iterable<CrewStatus> statuses});

class MorningEntry {
  final String id, username, displayName, avatarColor;
  final DateTime? wokeAt;      // null → still below the marker
  final bool onTime;
  final int lateMinutes;       // 0 unless late
  final int streak;
  final CrewStatus status;
  final bool isMe;
  final List<FeedReaction> reactions;
  final String? feedId;        // null when the row came from status only
}

class MorningLine {
  final MorningPhase phase;
  final List<MorningEntry> up;       // ascending by wokeAt
  final List<MorningEntry> pending;  // by crewStatusStyle rank, then username
  final int total;
  MorningEntry? get first;           // earliest riser, or null
}

MorningLine buildMorningLine({required DateTime now, required List<CrewMember> friends,
    required Map<String, CrewStatus> statuses, required List<FeedItem> feed,
    String? myId, String? myUsername, String? myDisplayName, String? myAvatarColor});
```

Only *today's local-day* feed items count as "up". Your own feed item produces the
`isMe` row; when you have no feed item today you appear in `pending` with your own
status. `lateMinutes` comes from the feed item's `wokeAt` minus the earliest
`wokeAt` of that day? **No** — the feed carries no scheduled time, so
`lateMinutes` is 0 and the verdict is "woke up" whenever `onTime` is false. (Do
not invent a lateness the data cannot support.)

- [ ] Test: `phase is tonight from 21:00 and before 04:00`
- [ ] Test: `phase is window while anyone is waking`
- [ ] Test: `phase is window within three hours of the last wake`
- [ ] Test: `phase is window before 10:00 even with nothing logged`
- [ ] Test: `phase is wrapped after 10:00 once the window has gone quiet`
- [ ] Test: `up is ascending by wake time and pending is ranked by status`
- [ ] Test: `only today's wakes count as up`
- [ ] Test: `you appear in up when you have woken, in pending when you have not`
- [ ] Test: `first names the earliest riser`
- [ ] Commit: `feat(domain): morning line — phase selection and timeline assembly`

---

### Task 4: `outcome_mark.dart` — one mark vocabulary

**Files:** Create `lib/ui/components/outcome_mark.dart` ·
Test `test/ui/components/outcome_mark_test.dart`

**Produces:**

```dart
Color outcomeColor(RhythmOutcome o);
String outcomeLabel(RhythmOutcome o);          // 'on time', 'late', 'slept through', 'rest day', 'no alarm'
void paintOutcomeMark(Canvas canvas, Offset center, RhythmOutcome outcome,
    {required double radius, required Color surface, bool freeze = false, bool square = false});
class OutcomeMark extends StatelessWidget { const OutcomeMark(this.outcome,
    {this.size = 11, this.freeze = false, this.square = false}); }
class OutcomeLegend extends StatelessWidget { const OutcomeLegend({this.outcomes}); }
```

`paintOutcomeMark` is the single implementation; `OutcomeMark` wraps it in a
`CustomPaint` so widgets and painters can never diverge. Shapes: filled, hollow
ring (2.2 px), cross, dash, ring+pip (freeze), 2 px baseline dot.

- [ ] Test: `every outcome has a distinct non-empty label`
- [ ] Test: `late never uses the danger colour` (the no-shame rule)
- [ ] Test: `OutcomeMark renders one CustomPaint per mark`
- [ ] Test: `OutcomeLegend labels every outcome it shows`
- [ ] Commit: `feat(ui): shared outcome mark vocabulary — shape first, colour second`

---

### Task 5: `wake_rhythm_chart.dart`

**Files:** Create `lib/ui/components/wake_rhythm_chart.dart` ·
Test `test/ui/components/wake_rhythm_chart_test.dart`

**Produces:** `WakeRhythmChart({required List<RhythmDay> days, double height = 176,
bool showList = true})` — painter draws gridlines + clock labels, the stepped
target ribbon (`ringMinute` → `graceEndMinute`), the connecting hairline, then the
marks via `paintOutcomeMark`. Below: `OutcomeLegend`, the summary line, and a
**Show as a list** toggle that swaps the chart for exact times.

- [ ] Test: `renders a chart for a fortnight of mornings`
- [ ] Test: `an empty fortnight shows the no-data card, never an empty axis`
- [ ] Test: `Show as a list reveals exact wake times`
- [ ] Test: `shouldRepaint is false for identical day lists`
- [ ] Commit: `feat(ui): wake-time rhythm chart with the on-time window as its band`

---

### Task 6: `consistency_grid.dart`

**Files:** Create `lib/ui/components/consistency_grid.dart` ·
Test `test/ui/components/consistency_grid_test.dart`

**Produces:** `ConsistencyGrid({required List<RhythmDay> days})` — 35 cells, five
Monday-first weeks, weekday headers, today ringed, tally line beneath.

- [ ] Test: `renders 35 cells with Monday-first weekday headers`
- [ ] Test: `today is ringed`
- [ ] Test: `the tally counts each outcome`
- [ ] Commit: `feat(ui): 35-day consistency grid`

---

### Task 7: `morning_line.dart` (view)

**Files:** Create `lib/ui/components/morning_line_view.dart` ·
Test `test/ui/components/morning_line_view_test.dart`

**Produces:** `MorningLineView({required MorningLine line, required DateTime now,
required void Function(MorningEntry) onOpen, required void Function(MorningEntry, String) onReact,
Widget? footer})`, plus `NowMarker` (its own `RepaintBoundary`, breathing ring,
static under reduced motion).

- [ ] Test: `wake rows show the time, verdict and streak`
- [ ] Test: `the marker sits between up and pending in the window phase`
- [ ] Test: `no marker in the wrapped phase`
- [ ] Test: `a waking row promotes Cheer; your own row never does`
- [ ] Test: `people who never woke read as no wake logged, not as an error`
- [ ] Test: `reduced motion removes the marker animation`
- [ ] Commit: `feat(ui): the Morning Line — one time-ordered list of a morning`

---

### Task 8: `podium.dart`

**Files:** Create `lib/ui/components/podium.dart` · Test `test/ui/components/podium_test.dart`

**Produces:** `Podium({required List<CrewStanding> top, void Function(CrewStanding)? onTap})`
— 1st centre and tallest; degrades to 2 or 1 plinth without a gap.

- [ ] Test: `orders second, first, third left to right`
- [ ] Test: `two standings render two plinths, one renders one`
- [ ] Test: `your own plinth reads You`
- [ ] Commit: `feat(ui): leaderboard podium`

---

### Task 9: `medallion_rail.dart`

**Files:** Create `lib/ui/components/medallion_rail.dart` ·
Test `test/ui/components/medallion_rail_test.dart`

**Produces:** `MedallionRail({required List<Achievement> badges})` — earned first,
then the nearest unearned with its progress, then locked.

- [ ] Test: `earned badges lead and show the earned state`
- [ ] Test: `the next badge shows progress out of target`
- [ ] Commit: `feat(ui): achievements as a medallion rail`

---

### Task 10: `stat_summary.dart`

**Files:** Create `lib/ui/components/stat_summary.dart` ·
Test `test/ui/components/stat_summary_test.dart`

**Produces:** `StatSummary({required StreakStats streak, required List<RhythmDay> week,
required PeriodStats stats, required int? consistency, required StatsPeriod period,
required bool periodsLocked, required ValueChanged<StatsPeriod> onPeriod, String? deltaLine})`.

- [ ] Test: `shows the run, the week marks and the four figures`
- [ ] Test: `premium periods carry a lock and route to the paywall`
- [ ] Test: `the four figures reflow to a 2x2 at 320pt without truncating`
- [ ] Commit: `feat(ui): stats summary block — one run, one sentence, four figures`

---

### Task 11: Crew screen

**Files:** Modify `lib/ui/screens/crew_screen.dart` ·
Modify `test/ui/screens/crew_screen_test.dart`

Body becomes: header → requests pill → phase hero → `MorningLineView` → groups
strip. Hero variants per phase. Empty state is the line with your own row plus the
invitation card on the line. Signed-out is the dawn hero plus a labelled example
strip. A 30 s `Timer.periodic` drives `now`, scoped to the marker + hero.

- [ ] Keep passing (behaviour, not layout): add-friend flow, requests accept /
      decline / cancel, voice inbox, groups open, pull-to-refresh incl.
      `CrewService.reload()`, restoring skeleton, unconfigured vs configured hero.
- [ ] Replace layout assertions: chip strip → line rows; "Cheer them on" → Cheer
      affordance; add phase tests at 06:12 / 09:40 / 22:30.
- [ ] Test: `the window phase leads with the live count and the marker`
- [ ] Test: `tonight leads with your own alarm and a countdown`
- [ ] Test: `no crew shows the line with only you and the invitation on it`
- [ ] Test: `a stale load keeps the last-known line with its fetched-at chip`
- [ ] Commit: `feat(crew): rebuild the tab around the Morning Line`

---

### Task 12: Stats shell + Rhythm lens

**Files:** Modify `lib/ui/screens/stats_screen.dart` ·
Create `lib/ui/screens/stats/rhythm_lens.dart`

Shell keeps every currently-exported pure helper (`weekWakes`, `consistencyLine`,
`consistencyLineFor`, `averageAlertness`, `alertnessBand`, `DayWake`,
`premiumLockCard`) so existing imports still resolve. Body becomes header →
`StatSummary` → `SegmentedControl` → active lens, inside a `CustomScrollView`.

- [ ] Commit: `feat(stats): summary block and lens shell, Rhythm lens`

---

### Task 13: Progress lens

**Files:** Create `lib/ui/screens/stats/progress_lens.dart`

Risk banner (the old `_AccountabilityPingCard`), streak detail + run sparkline,
`MedallionRail`, alertness + trend + disclaimer, Rough night / Share.

- [ ] Commit: `feat(stats): Progress lens`

---

### Task 14: Crew lens + Stats tests

**Files:** Create `lib/ui/screens/stats/crew_lens.dart` ·
Modify `test/ui/screens/stats_screen_test.dart`

- [ ] Keep passing: signed-out prompt, ranked leaderboard, crew score, row tap →
      friend page, leaderboard skeleton, share success + failure, rough-night
      excuse, period toggle, alertness card + trend, achievements, insights, ping.
- [ ] Test: `each lens shows its own body and only its own`
- [ ] Test: `your row stays visible when you are outside the podium`
- [ ] Commit: `feat(stats): Crew lens with podium`

---

### Task 15: Group detail

**Files:** Modify `lib/ui/screens/group_detail_screen.dart` ·
Modify `test/ui/screens/group_detail_screen_test.dart`

- [ ] Keep passing: invite code, one merged roster, unranked members append, race
      folds into rows, start CTA, delete vs leave, remove via overflow, owner badge.
- [ ] Test: `the group's morning leads the page and the invite is near the end`
- [ ] Test: `a group of one reads as a share screen, not an empty leaderboard`
- [ ] Test: `a member sees who can start a race, not a dead button`
- [ ] Commit: `feat(group): morning first, race banner, podium, invite last`

---

### Task 16: Friend detail

**Files:** Modify `lib/ui/screens/friend_detail_screen.dart` ·
Modify `test/ui/screens/friend_detail_screen_test.dart`

- [ ] Keep passing: identity + live status, unknown status placeholder, mutual
      comparison, missing-standing fallback, nudge, voice, remove behind overflow.
- [ ] Test: `today leads with the wake and carries the three actions`
- [ ] Test: `a waking friend promotes Cheer`
- [ ] Test: `a friend with no history says what will appear, and still acts`
- [ ] Commit: `feat(friend): today first, then their rhythm, then you two`

---

### Task 17: Performance pass

**Files:** `crew_screen.dart`, `stats_screen.dart`, the two painters

- [ ] `SliverList.builder` for the line and the standings; `RepaintBoundary`
      around the marker and both charts; `shouldRepaint` on identity only.
- [ ] Confirm no `DateTime.now()` in any `build` outside the ticker's scope.
- [ ] Commit: `perf(ui): slivers, scoped ticker and repaint boundaries`

---

### Task 18: Verification

- [ ] `flutter analyze` → no issues
- [ ] `flutter test` → all green, count ≥ the 1106 baseline
- [ ] `flutter build apk --debug --dart-define-from-file=rise.env.json`
- [ ] Update `STATUS.md`; commit; merge to `main`.
