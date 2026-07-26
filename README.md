# Riserys

A social alarm app: reliable wake-ups, verified rather than self-reported, and a
crew who can see you get up. Flutter + Supabase, with native alarm engines on
both platforms.

Current state and what needs a human next: **[`STATUS.md`](STATUS.md)**.

## Getting a clone running

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # generates database.g.dart
```

### Two files are NOT in this repo

They're gitignored on purpose (they carry keys). Copy them from a machine that
already has them, or the app builds but the backend is invisible:

| File | Without it |
|------|-----------|
| `rise.env.json` (repo root) | **Sign-in disappears.** No Supabase, so no crew, groups, leaderboard or push. Alarms still work. |
| `android/app/google-services.json` | Android push notifications (crew nudges) fail to register. |

`rise.env.json` holds exactly three keys:

```json
{
  "SUPABASE_URL": "...",
  "SUPABASE_ANON_KEY": "...",
  "GOOGLE_SERVER_CLIENT_ID": "..."
}
```

### Every device build needs the env flag

```bash
flutter run       --dart-define-from-file=rise.env.json
flutter build apk --release --dart-define-from-file=rise.env.json
```

**Omitting `--dart-define-from-file` compiles a build with no auth configured, and
the sign-in button is hidden by design.** This has been mistaken for "the login
button was deleted" more than once — if sign-in is missing, check this flag first.

## Running the checks

```bash
flutter analyze     # must be clean
flutter test        # 1222 tests
```

## macOS / iOS

The iOS alarm engine (`ios/Runner/`, `UNUserNotificationCenter`-based) is written
and review-verified but **has never been compiled** — it was built on Windows,
where there is no iOS toolchain. Expect a first-compile pass of real errors. See
`docs/superpowers/specs/2026-07-20-rise-ios-engine.md` for the design and
`STATUS.md` for what's outstanding.

iOS push is not configured: `ios/Runner/GoogleService-Info.plist` does not exist
yet, so crew nudges won't arrive on iOS until it's added.

```bash
cd ios && pod install && cd ..
flutter build ios --dart-define-from-file=rise.env.json
```

## Layout

```
lib/
  domain/     pure logic, no I/O — streak folding, wake rhythm, the morning line,
              schedule maths. Where the real rules live, and where the tests are
              densest.
  data/       services and repositories. Every service has a Fake beside it, so
              widget tests never touch the network or the database.
  ui/
    screens/    one file per screen; stats/ splits into its three lenses
    components/ shared widgets, including the two CustomPainter charts
    state/      Riverpod providers (pinned at 2.6.1 — see pubspec)
    theme/      tokens.dart and typography.dart are the whole design system
supabase/     migrations and edge functions
docs/superpowers/  design specs and implementation plans, newest last
```

## Conventions worth knowing before editing

- **`AsyncValue.value` rethrows on error.** Use `valueOrNull` in any screen build,
  or one failed provider takes the whole tab down.
- **Loading is never signed-out.** `AsyncLoading` renders a skeleton;
  `AsyncData(null)` means signed out. Skeletons carry the loaded layout's exact
  geometry so nothing jumps.
- **Outcome marks are shape first, colour second.** On-time green and
  slept-through red are ~5 ΔE apart under deuteranopia, so colour alone cannot
  carry a value. `lib/ui/components/outcome_mark.dart` is the single source; every
  chart, grid and legend goes through it.
- **No infinite animations in a screen.** `AnimationController.repeat()` schedules
  a frame every 16 ms for as long as the screen is open, and makes `pumpAndSettle`
  impossible to satisfy.
- **Never bulk-edit Dart with PowerShell `Get-Content`/`Set-Content`** — it
  corrupts em-dashes and other non-ASCII.
