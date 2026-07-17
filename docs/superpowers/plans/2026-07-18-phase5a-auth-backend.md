# Phase 5a — Auth + backend foundation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an optional Supabase-backed account (Google sign-in, a `profiles` row with a claimed username, sign out / delete account) that is purely additive — the local alarm app is untouched, and the app runs unchanged with no credentials configured.

**Architecture:** An injectable `AuthService` (Supabase impl + a fake) makes the sign-in/session/username state machine testable without a backend. `SupabaseConfig` (via `--dart-define`) gates everything: unconfigured → Supabase never initializes and sign-in is hidden. RLS-guarded `profiles` table + SQL migrations + a setup guide are delivered for the user to apply.

**Tech Stack:** Flutter 3.35 / Dart 3.9, flutter_riverpod 2.6.1, `supabase_flutter`, `google_sign_in`, Postgres/RLS (Supabase), shadcn "Mono" design.

## Global Constraints

- **Offline-first is sacred:** the alarm/ring/snooze/missions/stats path never awaits the network; auth is additive. No existing local test may break.
- **Degrade gracefully:** with no `--dart-define` credentials, `SupabaseConfig.isConfigured == false` → `main()` skips `Supabase.initialize`, `authServiceProvider` yields a `DisabledAuthService`, and the Profile shows the unchanged guest card (no sign-in). The app builds + runs + passes all tests with zero credentials.
- **Google-only** sign-in (Apple later, with iOS). `flutter_riverpod` 2.6.1; design tokens; injectable-service + fake pattern (like `PermissionGateway`).
- The real `SupabaseAuthService` and the SQL/RLS are **build-verified + review-verified** (no live backend in CI); the interface, fakes, providers, and UI are **unit/widget-tested** via `FakeAuthService`.
- `database.g.dart` stays gitignored; `alarm_api.g.dart` stays committed. **TDD, teeth-first.**

## File Structure

- `pubspec.yaml` — add `supabase_flutter`, `google_sign_in` (Task 1).
- `lib/config/supabase_config.dart` — `SupabaseConfig` (Task 1).
- `lib/main.dart` — config-gated `Supabase.initialize` (Task 1).
- `lib/domain/rise_account.dart` — `RiseAccount` (Task 2).
- `lib/data/auth/auth_service.dart` — `AuthService` interface + `FakeAuthService` + `DisabledAuthService` (Task 3).
- `lib/data/auth/supabase_auth_service.dart` — `SupabaseAuthService` (Task 5).
- `lib/ui/state/auth_providers.dart` — `authServiceProvider`, `accountProvider` (Task 4).
- `lib/ui/screens/username_claim_screen.dart` — claim UI (Task 6).
- `lib/ui/screens/profile_screen.dart` — account integration (Task 7).
- `lib/ui/screens/app_shell.dart` / `lib/main.dart` — account/claim routing (Task 8).
- `supabase/migrations/0001_profiles.sql`, `supabase/functions/delete-account/…` — schema/RLS/function (Task 9).
- `docs/superpowers/social/2026-07-18-supabase-setup-5a.md` — setup guide (Task 9).

---

### Task 1: Dependencies + `SupabaseConfig` + config-gated init

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/config/supabase_config.dart`
- Modify: `lib/main.dart`
- Test: `test/config/supabase_config_test.dart`

**Interfaces:**
- Produces: `SupabaseConfig` with `static const url/anonKey/googleServerClientId` (from `String.fromEnvironment`), `static bool get isConfigured`, and a pure `static bool configured(String, String, String)`. `main()` calls `Supabase.initialize` only when `isConfigured`, wrapped so a failure never blocks `runApp`.

- [ ] **Step 1: Add the packages**

```bash
flutter pub add supabase_flutter google_sign_in
```
Expected: `pubspec.yaml` gains both; `flutter pub get` clean.

- [ ] **Step 2: Write the failing config test**

Create `test/config/supabase_config_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/config/supabase_config.dart';

void main() {
  test('configured requires all three values non-empty', () {
    expect(SupabaseConfig.configured('u', 'k', 'c'), isTrue);
    expect(SupabaseConfig.configured('', 'k', 'c'), isFalse);
    expect(SupabaseConfig.configured('u', '', 'c'), isFalse);
    expect(SupabaseConfig.configured('u', 'k', ''), isFalse);
  });

  test('isConfigured is false with no --dart-define values (test env)', () {
    // In `flutter test` no dart-defines are set, so the const values are empty.
    expect(SupabaseConfig.isConfigured, isFalse);
  });
}
```

- [ ] **Step 3: Run to verify it fails**

```bash
flutter test test/config/supabase_config_test.dart
```
Expected: FAIL — `supabase_config.dart` not found.

- [ ] **Step 4: Write `SupabaseConfig`**

Create `lib/config/supabase_config.dart`:

```dart
/// Backend credentials, supplied at build time via --dart-define. When any is
/// missing the app runs fully local (Supabase is never initialised and sign-in
/// is hidden) — so the app builds and runs with no credentials at all.
class SupabaseConfig {
  static const url = String.fromEnvironment('SUPABASE_URL');
  static const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const googleServerClientId =
      String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  static bool get isConfigured => configured(url, anonKey, googleServerClientId);

  static bool configured(String url, String anonKey, String clientId) =>
      url.isNotEmpty && anonKey.isNotEmpty && clientId.isNotEmpty;
}
```

- [ ] **Step 5: Gate `Supabase.initialize` in `main.dart`**

In `lib/main.dart`, add imports:

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
```

In `main()`, AFTER `WidgetsFlutterBinding.ensureInitialized();`/`tzdata.initializeTimeZones();` and BEFORE the alarm startup (`AppSettings.load()` etc.), add:

```dart
  // Optional social backend. Additive and best-effort: a failure here must
  // never stop the local alarm app from launching.
  if (SupabaseConfig.isConfigured) {
    try {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        anonKey: SupabaseConfig.anonKey,
      );
    } catch (e) {
      debugPrint('Rise: Supabase init failed (social disabled): $e');
    }
  }
```

- [ ] **Step 6: Run tests, analyze, build unconfigured, commit**

```bash
flutter test test/config/supabase_config_test.dart
flutter test
flutter analyze
flutter build apk --debug
```
Expected: config tests green; whole suite green (nothing broke — Supabase isn't initialised in tests); `No issues found!`; the APK builds with NO `--dart-define` (proving the unconfigured path compiles + links).

```bash
git add pubspec.yaml pubspec.lock lib/config/supabase_config.dart lib/main.dart test/config/supabase_config_test.dart
git commit -m "feat(auth): add Supabase/Google deps + config-gated init (unconfigured = local-only)"
```

---

## Remaining tasks (Tasks 2–10 — full code written just before each is executed)

Each gets its complete code just before dispatch (same flow as prior plans). Summary + interfaces:
- **Task 2 — `RiseAccount`** (`rise_account.dart`): `{id, username?, displayName, avatarColor, email?}` + `copyWith`/`==`/`hashCode`; `bool get needsUsername => username == null`. Unit tests.
- **Task 3 — `AuthService` + fakes** (`auth_service.dart`): the interface (from the spec) + `FakeAuthService` (in-memory: sign-in emits an account with `username==null`; `claimUsername` sets it; `signOut`/`deleteAccount` emit null; `isUsernameAvailable` against an in-memory taken-set; a taken username throws on claim) + `DisabledAuthService` (streams null, sign-in throws `StateError('auth not configured')`). Unit tests over the fake's state machine.
- **Task 4 — Auth providers** (`auth_providers.dart`): `authServiceProvider` returns `SupabaseAuthService` when `SupabaseConfig.isConfigured` else `DisabledAuthService` (overridable with the fake in tests); `accountProvider = StreamProvider<RiseAccount?>((ref) => ref.watch(authServiceProvider).account())`. Provider tests with the fake.
- **Task 5 — `SupabaseAuthService`** (`supabase_auth_service.dart`): the real impl — `google_sign_in` (with `serverClientId`) → `Supabase.instance.client.auth.signInWithIdToken(OAuthProvider.google, idToken:, accessToken:)`; `account()` maps `onAuthStateChange` + a `profiles` fetch to `RiseAccount`; `claimUsername` inserts the row; `deleteAccount` calls the `delete-account` function. **Build-verified only** (no unit test — needs a live backend); the implementer adapts the exact API to the installed `supabase_flutter`/`google_sign_in` versions so `flutter build apk` compiles.
- **Task 6 — Username-claim screen** (`username_claim_screen.dart`): a format-validated (3–20, `[a-z0-9_]`) + availability-checked username field + display-name field + Claim button; calls `claimUsername`. Widget tests with the fake (valid claim calls the service; invalid format disables Claim; a taken name shows an error).
- **Task 7 — Profile account integration** (`profile_screen.dart`): signed out + configured → "Sign in with Google"; signed in → username + avatar chip + Sign out + Delete account (typed confirm); unconfigured → the unchanged guest card. Widget tests with the fake across the three states.
- **Task 8 — Account/claim routing** (`app_shell.dart`/`main.dart`): when the account has `needsUsername`, present the claim screen (over the shell, like the editor overlay) until claimed. Widget test: a signed-in-without-username account shows the claim screen; a claimed account shows the shell.
- **Task 9 — SQL migrations + setup guide** (`supabase/migrations/0001_profiles.sql`, `supabase/functions/delete-account/index.ts`, `docs/superpowers/social/2026-07-18-supabase-setup-5a.md`): the `profiles` table + RLS (own-row select/insert/update; username unique + format check), the `delete-account` edge function (service-role: delete the auth user, cascade removes the row), and the click-by-click setup guide (Supabase project, Google OAuth Android+Web clients, enable Google provider, apply migrations, the three `--dart-define`s, a device smoke test). Review-verified; no automated test.
- **Task 10 — Verify + merge:** `flutter test` green, `flutter analyze` clean, `flutter build apk --debug` (unconfigured) succeeds; final whole-branch review; merge `phase5a` → `main`. (Real Google sign-in + the SQL are verified by the user when they wire the backend.)
