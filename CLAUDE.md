# Riserys — working notes for Claude Code

Read [`STATUS.md`](STATUS.md) first: it says what shipped last and what needs a
human. [`README.md`](README.md) has clone setup. Design specs and implementation
plans live in `docs/superpowers/` — newest last.

## Build and verify

```bash
flutter analyze              # must be clean before any commit
flutter test                 # 1222 tests; keep them green
dart run build_runner build --delete-conflicting-outputs   # after schema changes
```

**Every device build needs `--dart-define-from-file=rise.env.json`.** Omitting it
compiles a build with no auth configured, and the sign-in button is hidden by
design. This has been reported as "the login button was deleted" more than once —
if sign-in is missing, check the flag before debugging anything else.

```bash
flutter build apk --release --dart-define-from-file=rise.env.json
```

`rise.env.json` and `android/app/google-services.json` are gitignored and carry
keys. Never commit them, never print their contents.

## Non-negotiables

- **Riverpod is pinned at 2.6.1.** Do not upgrade it as a side effect.
- **The alarm path is sacred.** Ring, dismiss, snooze and scheduling are the
  product. Social features are additive and must degrade to nothing when the
  backend is unconfigured — no account must never break an alarm.
- **Four privacy invariants.** Home coordinates never leave the device (only a
  derived "left home" boolean, and only on explicit opt-in). Push text is always
  server-composed, never client-supplied.
- **Wellness, not medical.** The alertness score is a wellness insight. Its
  disclaimer stays on its card. Nothing may imply a diagnostic reading.
- **Never shame a miss.** A missed morning is stated plainly and never coloured
  as a failure. Late is neutral ink, not `danger`.

## Patterns that were bugs first

- **`AsyncValue.value` rethrows on error** — use `valueOrNull` in screen builds.
  Reading `.value` on six providers is what let one failed provider take the
  whole Crew tab down.
- **Loading is never signed-out.** `AsyncLoading` → skeleton;
  `AsyncData(null)` → signed out. Skeletons carry the loaded layout's exact
  geometry so nothing jumps when data lands.
- **Social providers stay non-`autoDispose`**, keyed to
  `accountProvider.select((a) => a.value?.id)` — that keying is cross-account
  cache safety, not an optimisation.
- **Supabase stream services withhold their placeholder** until the first real
  load (`_loaded`/`_primed`). Don't re-add an eager `yield _current`.
- **No `AnimationController.repeat()` in a screen.** It schedules a frame every
  16 ms for as long as the screen is open, and makes `pumpAndSettle` impossible
  to satisfy. Use a finite pulse.
- **Outcome marks are shape first, colour second.** On-time green and
  slept-through red are ~5 ΔE apart under deuteranopia, so colour alone cannot
  carry a value. `lib/ui/components/outcome_mark.dart` is the single
  implementation; the chart, grid, rail and legends all go through it. Don't drop
  the shapes and keep the colours.
- **Never bulk-edit Dart with PowerShell `Get-Content`/`Set-Content`** — it
  corrupts em-dashes and other non-ASCII. Use the Edit tool.

## Where things live

`lib/domain/` is pure logic with no I/O and carries the densest tests — put new
rules there, not in a widget. `lib/data/` services each have a `Fake` beside them,
so widget tests never touch the network or the database. `lib/ui/theme/tokens.dart`
and `typography.dart` are the entire design system; adding a colour there should
be a deliberate decision, not a convenience.

## Testing notes

Screens that read the clock take a `clock:` parameter as a test seam
(`CrewScreen(clock:)`, `StatsScreen(clock:)`) — pin it, or a suite run at 22:00
asserts against a different screen than one run at 08:00. `flutter test` uses a
test font where every glyph is a full em box, so a layout that only fits with real
metrics will report a false overflow; fix the layout rather than the test.

## Platform state

Android is the developed platform. **The iOS alarm engine has never been
compiled** — written and review-verified on Windows, where there is no iOS
toolchain. Expect a real first-compile error pass. iOS push is unconfigured
(`ios/Runner/GoogleService-Info.plist` does not exist).
