# Phase 6 — Alertness Engine (mini-PVT) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a scientifically-grounded Psychomotor Vigilance Task (PVT) dismiss mission that both wakes the user and measures a 0–100 alertness score, persisted to the wake event and surfaced honestly in Stats.

**Architecture:** Pure-Dart PVT metrics + scoring in `lib/domain/pvt.dart` (fully unit-tested, no Flutter). A `PvtMission` widget in `lib/ui/missions/` plugs into the existing `buildMission` switch exactly like the other missions. The score is threaded mission → `RingScreen` → `WakeRecorder.finalizeDismiss` → `WakeEventRepository` and stored as a new nullable Drift column via an idempotent schema migration. Stats reads it back.

**Tech Stack:** Flutter 3.35 / Dart 3.9, flutter_riverpod 2.6.1 (2.x API only), Drift SQLite.

## Global Constraints
- **flutter_riverpod pinned 2.6.1** — 2.x API only (no `Ref` unified type, no `@riverpod` codegen).
- **Pure-Dart domain gets unit tests; widgets get widget tests.** Inject `Random`/timing so tests are deterministic — follow the existing `math_mission.dart` (`rng`) and `tap_mission.dart` (`targetTaps`) injection pattern.
- **The mission MUST NEVER trap the user.** Dismissal completes when the required number of valid taps is collected — *never* gated on achieving a minimum score. A low score is recorded, not punished (anti-shame red line from the synthesis).
- **Honest copy only.** The score is "reaction-speed alertness," never a medical/sleep-stage claim. No "abnormal"/diagnostic framing anywhere.
- **Difficulty strings are `'easy' | 'medium' | 'hard'`** to match `Alarm.missionDiff`.
- **Mission id string is `'pvt'`.** Register it in `buildMission` and the Create/Edit picker; extend the doc comment on `Alarm.mission`.
- Existing baseline: 350 tests green, `flutter analyze` clean. Keep both green.

---

### Task 6.1: PVT metrics engine (pure Dart)

**Files:**
- Create: `lib/domain/pvt.dart`
- Test: `test/domain/pvt_test.dart`

**Interfaces:**
- Produces:
  - `class PvtConfig { final int trials; final int isiMinMs; final int isiMaxMs; final int lapseThresholdMs; const PvtConfig(...); }`
  - `PvtConfig pvtConfigFor(String diff)` → easy: 3 trials, medium: 5, hard: 7; all `isiMinMs: 1500, isiMaxMs: 4000, lapseThresholdMs: 355` (PVT-B).
  - `class PvtResult { final int validTaps; final int lapses; final int falseStarts; final int meanRtMs; final int medianRtMs; final int minRtMs; final int maxRtMs; const PvtResult(...); }`
  - `PvtResult computePvtResult(List<int> reactionTimesMs, {required int falseStarts, int lapseThresholdMs = 355})` — computes metrics over the collected valid reaction times. `lapses` = count of RTs > `lapseThresholdMs`. Rounds mean to nearest int. Median = middle element of the sorted list (mean of two middles if even). If `reactionTimesMs` is empty, all RT metrics are 0.

- [ ] **Step 1: Write the failing test** — cover: `pvtConfigFor` trial counts per difficulty; `computePvtResult` mean/median/min/max on a known list `[250, 300, 400, 500]` (mean 363, median 350, min 250, max 500); lapse counting at threshold 355 (`[300, 356, 500]` → 2 lapses); empty list → zeros; falseStarts passed through.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/pvt.dart';

void main() {
  test('pvtConfigFor scales trials by difficulty', () {
    expect(pvtConfigFor('easy').trials, 3);
    expect(pvtConfigFor('medium').trials, 5);
    expect(pvtConfigFor('hard').trials, 7);
    expect(pvtConfigFor('easy').lapseThresholdMs, 355);
  });

  test('computePvtResult computes metrics', () {
    final r = computePvtResult([250, 300, 400, 500], falseStarts: 1);
    expect(r.validTaps, 4);
    expect(r.meanRtMs, 363); // 1450/4 = 362.5 → 363
    expect(r.medianRtMs, 350); // (300+400)/2
    expect(r.minRtMs, 250);
    expect(r.maxRtMs, 500);
    expect(r.lapses, 1); // only 400? no — >355: 400,500 → 2
    expect(r.falseStarts, 1);
  });

  test('empty reaction times yield zeroed metrics', () {
    final r = computePvtResult([], falseStarts: 0);
    expect(r.validTaps, 0);
    expect(r.meanRtMs, 0);
    expect(r.lapses, 0);
  });
}
```
*(Note: fix the lapse expectation to 2 in the assertion above when writing — `400` and `500` both exceed 355.)*

- [ ] **Step 2: Run test to verify it fails** — `flutter test test/domain/pvt_test.dart` → FAIL (pvt.dart missing).
- [ ] **Step 3: Implement `lib/domain/pvt.dart`** — the three types + `pvtConfigFor` + `computePvtResult` per the Interfaces block. No Flutter imports.
- [ ] **Step 4: Run test to verify it passes.**
- [ ] **Step 5: Commit** — `feat(pvt): PVT metrics engine (config, result, computation)`.

---

### Task 6.2: Alertness score (pure Dart)

**Files:**
- Modify: `lib/domain/pvt.dart`
- Test: `test/domain/pvt_test.dart`

**Interfaces:**
- Produces: `int alertnessScore(PvtResult r)` → integer 0–100.
- Formula (exact, testable):
  - `rtComponent = 100 * (600 - meanRtMs) / (600 - 220)`, clamped to `0..100` (220 ms ≈ ceiling-fast, 600 ms ≈ floor).
  - `penalty = lapses * 8 + falseStarts * 5`.
  - `score = (rtComponent - penalty).round().clamp(0, 100)`.
  - If `validTaps == 0` → return `0`.

- [ ] **Step 1: Write the failing test** — sharp session `PvtResult(validTaps:4, lapses:0, falseStarts:0, meanRtMs:250, ...)` → 92; groggy `meanRtMs:480, lapses:3` → `(100*(600-480)/380 = 31.6) - 24 = 7.6 → 8`; a mean below 220 clamps rtComponent to 100; zero valid taps → 0.
- [ ] **Step 2: Run to verify it fails.**
- [ ] **Step 3: Implement `alertnessScore`.**
- [ ] **Step 4: Run to verify it passes.**
- [ ] **Step 5: Commit** — `feat(pvt): alertness score (0–100) from PVT metrics`.

---

### Task 6.3: PVT mission widget

**Files:**
- Create: `lib/ui/missions/pvt_mission.dart`
- Test: `test/ui/missions/pvt_mission_test.dart`

**Interfaces:**
- Consumes: `pvtConfigFor`, `computePvtResult`, `alertnessScore` (Task 6.1/6.2); `MissionFrame` (`lib/ui/missions/mission_frame.dart`).
- Produces: `class PvtMission extends StatefulWidget` with `final String diff; final VoidCallback onSolved; final void Function(int alertnessScore)? onResult;` plus test injection hooks: `final PvtConfig? config;` (override difficulty config) and `final int Function()? nowMs;` (injectable millisecond clock so tests control reaction time instead of wall-clock) and `final List<int>? scriptedIsiMs;` (deterministic ISI sequence; falls back to `Random`).

**Behavior:**
- Runs `config.trials` trials. Each trial: a **wait** phase of a random ISI (`scriptedIsiMs[i]` if provided, else `isiMin..isiMax`), during which the target shows a neutral "Wait…" state; a tap here is a **false start** (increment counter, no RT, restart the *same* trial's wait).
- After the ISI, the target flips to a "TAP!" state and a stopwatch starts (via `nowMs()` or `DateTime.now().millisecondsSinceEpoch`). The user's tap records `RT = nowMs_at_tap - nowMs_at_stimulus`.
- After the last trial: `final result = computePvtResult(rts, falseStarts: fs); onResult?.call(alertnessScore(result)); onSolved();`.
- UI via `MissionFrame(instruction: 'Tap the moment it turns green' , child: ...)`; show trial progress (e.g. "3 / 5") and the tap target (reuse the Mono token styling from `tap_mission.dart`). Respect `MediaQuery.disableAnimations` for any pulse.

- [ ] **Step 1: Write the failing widget test** — pump `PvtMission(diff:'easy', config: PvtConfig(trials:1, isiMinMs:0, isiMaxMs:0, lapseThresholdMs:355), scriptedIsiMs:[0], nowMs: <controllable>, onResult: capture, onSolved: flag)`; drive one trial: after the ISI elapses, tap the target, advance `nowMs` by a known delta, assert `onSolved` fired once and `onResult` received a plausible score. Also assert a tap during the wait phase does **not** solve the mission (false-start path).
- [ ] **Step 2: Run to verify it fails.**
- [ ] **Step 3: Implement `PvtMission`.** Use a `Timer`/`Ticker` gated on the injectable clock; ensure timers are cancelled in `dispose`.
- [ ] **Step 4: Run to verify it passes.**
- [ ] **Step 5: Commit** — `feat(pvt): PVT dismiss-mission widget`.

---

### Task 6.4: Register the mission + Create/Edit picker + score plumbing hook

**Files:**
- Modify: `lib/ui/missions/mission_host.dart` (add `'pvt'` case; extend `buildMission` signature)
- Modify: `lib/ui/screens/ring_screen.dart` (`MissionBuilder` typedef + gate wiring)
- Modify: `lib/ui/screens/create_edit_screen.dart` (add the picker option + label)
- Modify: `lib/domain/alarm.dart` (extend the `mission` doc comment to include `'pvt'`)
- Test: `test/ui/screens/ring_screen_test.dart` (or the existing mission-builder test) + a Create/Edit widget test if one exists.

**Interfaces:**
- Change `MissionBuilder` typedef and `buildMission` to carry an optional alertness callback:
  `typedef MissionBuilder = Widget Function(BuildContext context, Alarm alarm, VoidCallback onSolved, void Function(int alertnessScore)? onAlertness);`
  and `Widget buildMission(BuildContext, Alarm, VoidCallback onSolved, [void Function(int)? onAlertness])`. Only the `'pvt'` case forwards `onAlertness` into `PvtMission.onResult`; every other mission ignores it (so behavior is unchanged).
- In `RingScreen`, add `int? _pendingAlertness;` state. The gate passes `(score) => _pendingAlertness = score` as `onAlertness`; `_dismiss('mission')` is unchanged in signature but Task 6.5 makes `finalizeDismiss` receive `_pendingAlertness`.

- [ ] **Step 1: Write/extend the failing test** — a widget test that builds a `RingScreen` with a `'pvt'` alarm and the real `buildMission`, asserts the PVT mission renders; and asserts the Create/Edit screen lists an "Alertness (PVT)" option. (Follow whatever pattern the existing ring/create-edit tests use.)
- [ ] **Step 2: Run to verify it fails.**
- [ ] **Step 3: Implement** the signature change, the `'pvt'` case, the picker entry (label **"Alertness (PVT)"**, id `'pvt'`), and the `Alarm.mission` doc comment. Update all existing `buildMission`/`MissionBuilder` call sites to the new arity (the optional param keeps them compiling; pass through where a real `onAlertness` is available).
- [ ] **Step 4: Run to verify it passes** — plus `flutter analyze` clean and the full suite green (signature change touches shared code).
- [ ] **Step 5: Commit** — `feat(pvt): register PVT mission in picker + ring, thread alertness callback`.

---

### Task 6.5: Persist the alertness score

**Files:**
- Modify: `lib/domain/wake_event.dart` (add `final int? alertnessScore;` — constructor, `copyWith`, `==`, `hashCode`, `toString`)
- Modify: the Drift database + WakeEvents table + migration (under `lib/data/local/` — read the existing `wake_event` table + the existing v2→v3 migration and follow that exact pattern)
- Modify: `lib/data/local/wake_event_repository.dart` (`finalizeDismiss` gains an optional `int? alertnessScore` and writes it)
- Modify: `lib/data/wake_recorder.dart` (`finalizeDismiss` forwards optional `int? alertnessScore`)
- Modify: `lib/ui/screens/ring_screen.dart` (pass `_pendingAlertness` into `finalizeDismiss`)
- Test: the existing wake-event repository/migration test + wake_event domain test.

**Interfaces:**
- `WakeEvent` gains nullable `alertnessScore` (null = not a PVT dismissal / no score).
- Drift: **add a nullable integer column `alertness_score`**, bump the schema version by 1, and add an idempotent migration step that mirrors the existing wake_events migration (add-column guarded so re-running is safe). Do **not** rewrite existing rows.
- `WakeEventRepository.finalizeDismiss(...)` and `WakeRecorder.finalizeDismiss(...)` both gain `{int? alertnessScore}`.

- [ ] **Step 1: Write the failing test** — domain: a `WakeEvent` round-trips `alertnessScore` through `copyWith`/equality. Repository/migration: opening a ring then `finalizeDismiss(alarmId, method:'mission', alertnessScore: 84)` reads back an event with `alertnessScore == 84`; and a non-PVT dismissal reads back `null`. Migration test: an existing DB at the prior schema version upgrades without data loss and the new column exists.
- [ ] **Step 2: Run to verify it fails.**
- [ ] **Step 3: Implement** the domain field, the Drift column + version bump + idempotent migration, and thread the parameter through both `finalizeDismiss` methods and the `RingScreen` call site (`finalizeDismiss(widget.alarmId, method: method, alertnessScore: _pendingAlertness)`). Regenerate Drift codegen (`dart run build_runner build --delete-conflicting-outputs`) — note `database.g.dart` is gitignored; do not commit it.
- [ ] **Step 4: Run to verify it passes** — full suite + `flutter analyze`.
- [ ] **Step 5: Commit** — `feat(pvt): persist alertness score on wake events (schema migration)`.

---

### Task 6.6: Surface alertness in Stats

**Files:**
- Modify: the Stats screen (`lib/ui/screens/stats_screen.dart` or equivalent — locate it) + any wake-stats provider/selector.
- Test: the Stats screen widget test + any pure selector test.

**Interfaces:**
- Consumes: `WakeEvent.alertnessScore` from the wake-events provider.
- Produces: a pure helper `int? averageAlertness(List<WakeEvent> events)` (mean of non-null scores, rounded; null if none) — unit-tested — and a Stats card showing **latest score**, **average**, and a small recent trend (reuse existing Stats card/graph components).

**Copy (verbatim intent):** header "Alertness" with subtext "Your reaction speed at wake-up — sharper is more awake. Not a medical measure." Never label a score "low/abnormal"; show the number + a neutral descriptor band (e.g. ≥80 "sharp", 50–79 "steady", <50 "groggy") framed as information, not judgement.

- [ ] **Step 1: Write the failing test** — `averageAlertness` over `[80, null, 90]` → 85, `[]`/all-null → null; a Stats widget test asserting the Alertness card renders the latest score + the honest subtext when events carry scores, and renders an empty/placeholder state when none do.
- [ ] **Step 2: Run to verify it fails.**
- [ ] **Step 3: Implement** the selector + the Stats card with the honest copy.
- [ ] **Step 4: Run to verify it passes** — full suite + `flutter analyze`.
- [ ] **Step 5: Commit** — `feat(pvt): surface alertness score + trend in Stats`.

---

## Self-review checklist (controller, before final review)
- Spec coverage: mission (6.3) + score (6.1/6.2) + persistence (6.5) + surface (6.6) + discoverability (6.4) all present.
- Anti-trap invariant honored: dismissal never blocked on score (6.3).
- Signature change (6.4) — every `buildMission`/`MissionBuilder` call site updated; suite green.
- No medical/abnormal framing in any copy (6.6).
- `database.g.dart` not committed (gitignored); `alarm_api.g.dart` remains the committed-codegen exception.
