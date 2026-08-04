# Login-First Launch Flow + Mission Preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the first screen a login screen (guest choice persisted, onboarding for everyone afterwards), and give every mission in the picker a Preview button that runs the real mission in a sandbox and returns to the exact picker state.

**Architecture:** The launch gate becomes a pure, synchronous decision (`lib/domain/launch_gate.dart`) fed by `AppSettings.guestChosen` and `AuthService.current`; a new `LoginScreen` is one of four possible homes. Mission preview is a lightweight sandbox screen pushed as a route over the open picker sheet, so the Navigator preserves the sheet's scroll/selection/config by construction.

**Tech Stack:** Flutter, Riverpod 2.6.1 (pinned), SharedPreferences, flutter_test. Spec: `docs/superpowers/specs/2026-08-04-login-first-and-mission-preview-design.md`.

## Global Constraints

- `flutter analyze` must be clean before every commit; the full `flutter test` suite (1222 existing + new) green at the end.
- Riverpod is pinned at 2.6.1. No new packages, no migrations, no backend changes.
- The alarm path is sacred: do not edit `ring_screen.dart` (except importing its `MissionBuilder` typedef), the mission widgets, the scheduler, or any native code.
- Loading is never signed-out: the gate reads only `AuthService.current` (synchronous), never the account stream.
- Never read `AsyncValue.value` in a build (`valueOrNull`); no `AnimationController.repeat()` in any screen.
- PowerShell shell: chain commands with `;` (never `&&`); commit messages ASCII-only; write/edit Dart files ONLY with the Edit/Write tools (PowerShell file-writes corrupt em-dashes).
- Copy rules: never shame a miss; wellness, not medical; the strings specified in tasks are verbatim.

---

### Task 1: Pure launch-gate decision

**Files:**
- Create: `lib/domain/launch_gate.dart`
- Test: `test/domain/launch_gate_test.dart`

**Interfaces:**
- Produces: `enum LaunchHome { startupFailed, login, onboarding, shell }` and
  `LaunchHome resolveLaunchHome({required bool repositoryReady, required bool authConfigured, required bool signedIn, required bool guestChosen, required bool onboardingComplete})`.
  Task 5 consumes both verbatim.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/launch_gate.dart';

void main() {
  group('resolveLaunchHome', () {
    test('startup failure wins over everything', () {
      expect(
        resolveLaunchHome(
          repositoryReady: false,
          authConfigured: true,
          signedIn: false,
          guestChosen: false,
          onboardingComplete: false,
        ),
        LaunchHome.startupFailed,
      );
    });

    test('unconfigured auth never sees login: onboarding then shell', () {
      expect(
        resolveLaunchHome(
          repositoryReady: true,
          authConfigured: false,
          signedIn: false,
          guestChosen: false,
          onboardingComplete: false,
        ),
        LaunchHome.onboarding,
      );
      expect(
        resolveLaunchHome(
          repositoryReady: true,
          authConfigured: false,
          signedIn: false,
          guestChosen: false,
          onboardingComplete: true,
        ),
        LaunchHome.shell,
      );
    });

    test('signed-in skips login; onboarding flag still applies', () {
      expect(
        resolveLaunchHome(
          repositoryReady: true,
          authConfigured: true,
          signedIn: true,
          guestChosen: false,
          onboardingComplete: false,
        ),
        LaunchHome.onboarding,
      );
      expect(
        resolveLaunchHome(
          repositoryReady: true,
          authConfigured: true,
          signedIn: true,
          guestChosen: false,
          onboardingComplete: true,
        ),
        LaunchHome.shell,
      );
    });

    test('a remembered guest skips login; onboarding flag still applies', () {
      expect(
        resolveLaunchHome(
          repositoryReady: true,
          authConfigured: true,
          signedIn: false,
          guestChosen: true,
          onboardingComplete: false,
        ),
        LaunchHome.onboarding,
      );
      expect(
        resolveLaunchHome(
          repositoryReady: true,
          authConfigured: true,
          signedIn: false,
          guestChosen: true,
          onboardingComplete: true,
        ),
        LaunchHome.shell,
      );
    });

    test('configured + known signed-out + no guest flag shows login — even '
        'before onboarding (login precedes onboarding)', () {
      expect(
        resolveLaunchHome(
          repositoryReady: true,
          authConfigured: true,
          signedIn: false,
          guestChosen: false,
          onboardingComplete: false,
        ),
        LaunchHome.login,
      );
      expect(
        resolveLaunchHome(
          repositoryReady: true,
          authConfigured: true,
          signedIn: false,
          guestChosen: false,
          onboardingComplete: true,
        ),
        LaunchHome.login,
      );
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/launch_gate_test.dart`
Expected: FAIL — "Target of URI doesn't exist: 'package:rise/domain/launch_gate.dart'".

- [ ] **Step 3: Write minimal implementation**

Create `lib/domain/launch_gate.dart`:

```dart
/// What the app shows as its home at launch. Pure and synchronous: every
/// input is already known on the first frame (settings are loaded in main()
/// before runApp, and the auth service primes its account synchronously from
/// the restored session), so there is no loading state at the gate — and a
/// signed-in user can never see the login screen flash ("loading is never
/// signed-out").
enum LaunchHome {
  /// Startup failed to configure the alarm repository: degrade visibly.
  startupFailed,

  /// Auth is configured, the user is known signed-out, and they have not
  /// chosen guest mode. The login screen is the front door.
  login,

  /// First run (or settings lost): the product tour + setup wizard.
  onboarding,

  /// The app itself.
  shell,
}

/// The single launch-gate decision.
///
/// Precedence: a broken startup beats everything; the auth question (login)
/// is asked exactly once — skipped entirely when auth is unconfigured, when
/// signed in, or when the guest choice was remembered — and onboarding comes
/// after it for everyone, signed-in and guest alike.
LaunchHome resolveLaunchHome({
  required bool repositoryReady,
  required bool authConfigured,
  required bool signedIn,
  required bool guestChosen,
  required bool onboardingComplete,
}) {
  if (!repositoryReady) return LaunchHome.startupFailed;
  final pastAuth = !authConfigured || signedIn || guestChosen;
  if (!pastAuth) return LaunchHome.login;
  return onboardingComplete ? LaunchHome.shell : LaunchHome.onboarding;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/domain/launch_gate_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

Run `flutter analyze` — expect "No issues found!". Then:

```powershell
git add lib/domain/launch_gate.dart test/domain/launch_gate_test.dart; git commit -m "feat(domain): pure launch-gate decision (login-first, guest remembered)"
```

---

### Task 2: `AppSettings.guestChosen` flag

**Files:**
- Modify: `lib/data/app_settings.dart`
- Test: `test/data/app_settings_test.dart`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `bool get guestChosen` and `Future<void> setGuestChosen(bool value)` on `AppSettings`. Tasks 3 and 5 consume both.

- [ ] **Step 1: Write the failing test**

Append to `test/data/app_settings_test.dart`, inside `main()`:

```dart
  test('guestChosen defaults false, round-trips, and persists', () async {
    SharedPreferences.setMockInitialValues({});
    final s = await AppSettings.load();
    expect(s.guestChosen, isFalse);

    await s.setGuestChosen(true);
    expect(s.guestChosen, isTrue);

    final s2 = await AppSettings.load();
    expect(s2.guestChosen, isTrue);

    await s2.setGuestChosen(false);
    final s3 = await AppSettings.load();
    expect(s3.guestChosen, isFalse);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/app_settings_test.dart`
Expected: FAIL — "The getter 'guestChosen' isn't defined for the type 'AppSettings'".

- [ ] **Step 3: Write minimal implementation**

In `lib/data/app_settings.dart`, directly after the `setOnboardingComplete`
method (line 23), add:

```dart
  static const _kGuestChosen = 'guestChosen';

  /// Whether the user chose "Continue as guest" on the login screen. The
  /// launch gate reads this to skip the login screen on later launches —
  /// the choice is remembered, never re-asked. Signing in clears it (the
  /// account supersedes the choice), so a later sign-out returns to login.
  bool get guestChosen => _prefs.getBool(_kGuestChosen) ?? false;

  Future<void> setGuestChosen(bool value) =>
      _prefs.setBool(_kGuestChosen, value);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/app_settings_test.dart`
Expected: PASS (all tests, old + new).

- [ ] **Step 5: Commit**

Run `flutter analyze` — expect clean. Then:

```powershell
git add lib/data/app_settings.dart test/data/app_settings_test.dart; git commit -m "feat(settings): persist guestChosen so the login gate is asked exactly once"
```

---

### Task 3: `LoginScreen`

**Files:**
- Create: `lib/ui/screens/login_screen.dart`
- Test: `test/ui/screens/login_screen_test.dart`

**Interfaces:**
- Consumes: `AppSettings.guestChosen` / `setGuestChosen` (Task 2); existing
  `authServiceProvider`, `appSettingsProvider`, `PrimaryButton`, `GhostButton`,
  `RiseToast`.
- Produces: `class LoginScreen extends ConsumerStatefulWidget` with
  `const LoginScreen({super.key, required this.onAdvance})` and
  `final VoidCallback onAdvance`. Task 5 consumes this verbatim.

- [ ] **Step 1: Write the failing test**

Create `test/ui/screens/login_screen_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/app_settings.dart';
import 'package:rise/data/auth/auth_service.dart';
import 'package:rise/ui/screens/login_screen.dart';
import 'package:rise/ui/state/auth_providers.dart';
import 'package:rise/ui/state/settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sign-in always fails, to exercise the never-trapping error path.
class _FailingAuth extends FakeAuthService {
  @override
  Future<void> signInWithGoogle() async => throw StateError('nope');
}

/// Sign-in hangs until released, to prove the double-tap guard.
class _SlowAuth extends FakeAuthService {
  int signInCalls = 0;
  final Completer<void> gate = Completer<void>();
  @override
  Future<void> signInWithGoogle() {
    signInCalls++;
    return gate.future;
  }
}

Future<AppSettings> _newStore({bool guest = false}) async {
  SharedPreferences.setMockInitialValues({});
  final store = await AppSettings.load();
  if (guest) await store.setGuestChosen(true);
  return store;
}

Widget _host(AppSettings store, AuthService auth, VoidCallback onAdvance) =>
    ProviderScope(
      overrides: [
        appSettingsProvider.overrideWithValue(store),
        authServiceProvider.overrideWithValue(auth),
      ],
      child: MaterialApp(home: LoginScreen(onAdvance: onAdvance)),
    );

void main() {
  testWidgets('renders both ways forward and the no-account promise', (t) async {
    final store = await _newStore();
    final fake = FakeAuthService();
    addTearDown(fake.dispose);
    await t.pumpWidget(_host(store, fake, () {}));
    await t.pumpAndSettle();

    expect(find.text('Welcome to Riserys'), findsOneWidget);
    expect(find.text('Sign in with Google'), findsOneWidget);
    expect(find.text('Continue as guest'), findsOneWidget);
    expect(find.text('Alarms always work without an account.'), findsOneWidget);
  });

  testWidgets('Continue as guest remembers the choice and advances without '
      'signing in', (t) async {
    var advanced = false;
    final store = await _newStore();
    final fake = FakeAuthService();
    addTearDown(fake.dispose);
    await t.pumpWidget(_host(store, fake, () => advanced = true));
    await t.pumpAndSettle();

    await t.tap(find.text('Continue as guest'));
    await t.pumpAndSettle();

    expect(store.guestChosen, isTrue);
    expect(advanced, isTrue);
    expect(fake.current, isNull, reason: 'guest never signs in');
  });

  testWidgets('Sign in with Google clears a prior guest choice and advances',
      (t) async {
    var advanced = false;
    final store = await _newStore(guest: true); // chose guest on a past launch
    final fake = FakeAuthService();
    addTearDown(fake.dispose);
    await t.pumpWidget(_host(store, fake, () => advanced = true));
    await t.pumpAndSettle();

    await t.tap(find.text('Sign in with Google'));
    await t.pumpAndSettle();

    expect(fake.current, isNotNull, reason: 'signed in');
    expect(store.guestChosen, isFalse,
        reason: 'the account supersedes the guest choice');
    expect(advanced, isTrue);
  });

  testWidgets('a failed sign-in shows the toast and never advances', (t) async {
    var advanced = false;
    final store = await _newStore();
    final fake = _FailingAuth();
    addTearDown(fake.dispose);
    await t.pumpWidget(_host(store, fake, () => advanced = true));
    await t.pumpAndSettle();

    await t.tap(find.text('Sign in with Google'));
    await t.pump(); // let the overlay toast insert

    expect(find.text('Sign-in didn\'t complete. Try again, or continue as guest.'),
        findsOneWidget);
    expect(advanced, isFalse);
    expect(store.guestChosen, isFalse, reason: 'guest is an explicit choice');
  });

  testWidgets('double-tapping sign-in fires exactly one attempt', (t) async {
    final store = await _newStore();
    final fake = _SlowAuth();
    addTearDown(fake.dispose);
    await t.pumpWidget(_host(store, fake, () {}));
    await t.pumpAndSettle();

    await t.tap(find.text('Sign in with Google'));
    await t.pump();
    await t.tap(find.text('Sign in with Google')); // blocked while signing in
    await t.pump();

    expect(fake.signInCalls, 1);
    fake.gate.complete();
    await t.pumpAndSettle();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/screens/login_screen_test.dart`
Expected: FAIL — "Target of URI doesn't exist: 'package:rise/ui/screens/login_screen.dart'".

- [ ] **Step 3: Write minimal implementation**

Create `lib/ui/screens/login_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../components/rise_buttons.dart';
import '../components/toast.dart';
import '../state/auth_providers.dart';
import '../state/settings_providers.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// The launch login screen — the first thing a user sees when auth is
/// configured, they are known signed-out, and they have not chosen guest
/// mode (see `resolveLaunchHome`). Two ways forward and no skip: guest IS
/// the skip, and both choices are remembered (guest by a flag, sign-in by
/// the account itself). This screen only reports completion via [onAdvance];
/// the gate in main.dart re-resolves and swaps in onboarding or the shell.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, required this.onAdvance});

  final VoidCallback onAdvance;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _signingIn = false;

  Future<void> _signIn() async {
    if (_signingIn) return;
    setState(() => _signingIn = true);
    try {
      await ref.read(authServiceProvider).signInWithGoogle();
    } catch (_) {
      if (mounted) {
        RiseToast.show(
            context,
            'Sign-in didn\'t complete. Try again, or continue as guest.',
            kind: RiseToastKind.error);
        setState(() => _signingIn = false);
      }
      return;
    }
    // Signed in. The account supersedes the guest choice — clear it so a
    // later sign-out returns here instead of skipping the screen. A prefs
    // hiccup must never block the advance, so the clear is best-effort.
    try {
      await ref.read(appSettingsProvider).setGuestChosen(false);
    } catch (_) {}
    if (mounted) setState(() => _signingIn = false);
    widget.onAdvance();
  }

  Future<void> _continueAsGuest() async {
    if (_signingIn) return;
    try {
      await ref.read(appSettingsProvider).setGuestChosen(true);
    } catch (_) {
      // Best-effort: a prefs failure must never trap anyone on a gate.
    }
    widget.onAdvance();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RiseColors.appBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: RiseColors.accentSoft,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Icon(Icons.wb_sunny_outlined,
                    size: 44, color: RiseColors.accent),
              ),
              const SizedBox(height: 28),
              Text('Welcome to Riserys',
                  textAlign: TextAlign.center, style: RiseText.display),
              const SizedBox(height: 12),
              Text(
                  'Sign in to back up your streak and wake with your crew — '
                  'or keep going solo.',
                  textAlign: TextAlign.center,
                  style: RiseText.body.copyWith(color: RiseColors.textDim)),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PrimaryButton(
                      label: 'Sign in with Google',
                      icon: Icons.login,
                      onPressed: _signingIn ? null : _signIn,
                    ),
                    if (_signingIn)
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: RiseColors.primaryText),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              GhostButton(
                label: 'Continue as guest',
                onPressed: _signingIn ? null : _continueAsGuest,
              ),
              const SizedBox(height: 14),
              Text('Alarms always work without an account.',
                  style: RiseText.caption),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/screens/login_screen_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

Run `flutter analyze` — expect clean. Then:

```powershell
git add lib/ui/screens/login_screen.dart test/ui/screens/login_screen_test.dart; git commit -m "feat(auth): LoginScreen - sign in or continue as guest, both remembered"
```

---

### Task 4: Onboarding loses its sign-in page

**Files:**
- Modify: `lib/ui/screens/onboarding_screen.dart`
- Test: `test/ui/screens/onboarding_screen_test.dart`

**Interfaces:**
- Consumes: nothing new (the sign-in UI moved to `LoginScreen`, Task 3).
- Produces: an `OnboardingScreen` with exactly six pages, identical for
  configured and unconfigured auth. No public API change (`onDone` stays).

- [ ] **Step 1: Update the tests first (watch them fail)**

In `test/ui/screens/onboarding_screen_test.dart`, DELETE the last two tests
(`'configured auth: appends a sign-in step; guest finishes'` and
`'configured auth: Sign in with Google signs in and finishes'`) and replace
them with:

```dart
  testWidgets('configured auth: identical six-page flow, no sign-in page',
      (t) async {
    var done = false;
    final fake = FakeAuthService();
    addTearDown(fake.dispose);
    final store = await _newStore();
    await t.pumpWidget(_host(_FakeGateway(_perms()), store,
        auth: fake, onDone: () => done = true));
    await t.pumpAndSettle();
    await _toPermissions(t);
    // The permissions page is the finish for everyone now; the auth choice
    // happened on the login screen before onboarding even started.
    expect(find.text('Start using Riserys'), findsOneWidget);
    expect(find.text('Save your progress'), findsNothing);
    expect(find.text('Sign in with Google'), findsNothing);
    expect(find.text('Continue as guest'), findsNothing);
    await t.tap(find.text('Start using Riserys'));
    await t.pumpAndSettle();
    expect(done, isTrue);
    expect(fake.current, isNull, reason: 'onboarding never signs in');
  });
```

Also update the existing `'unconfigured auth: no sign-in step (permissions is the
finish)'` test to assert the Google button is gone too — change its two
expects to:

```dart
    expect(find.text('Start using Riserys'), findsOneWidget);
    expect(find.text('Sign in with Google'), findsNothing);
    expect(find.text('Continue as guest'), findsNothing);
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/screens/onboarding_screen_test.dart`
Expected: FAIL — the new configured-auth test still finds "Save your progress".

- [ ] **Step 3: Remove the sign-in step**

In `lib/ui/screens/onboarding_screen.dart`:

1. Delete three imports (only used by the removed code):
   - `import '../../data/auth/auth_service.dart';`
   - `import '../components/toast.dart';`
   - `import '../state/auth_providers.dart';`
2. Delete the `_signingIn` field and its comment (lines 39-40).
3. Replace the `_signInStep` getter and `_lastPage` getter (lines 53-59) with:

```dart
  /// The last page index (permissions). The sign-in step moved out to the
  /// launch LoginScreen, so onboarding is the same six pages for everyone —
  /// configured or not, signed-in or guest.
  int get _lastPage => 5;
```

4. In the `PageView` children, delete `if (_signInStep) _signInPage(),`.
5. Replace the bottom button block (the `_signInStep && _page == _lastPage`
   ternary and its comment) with:

```dart
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  RiseSpacing.screen, 12, RiseSpacing.screen, 16),
              child: PrimaryButton(
                label: _page < _lastPage ? 'Next' : 'Start using Riserys',
                onPressed: _next,
              ),
            ),
```

6. Delete the `_signInPage()` and `_signInAndFinish()` methods entirely.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/screens/onboarding_screen_test.dart`
Expected: PASS (all tests).

- [ ] **Step 5: Commit**

Run `flutter analyze` — expect clean. Then:

```powershell
git add lib/ui/screens/onboarding_screen.dart test/ui/screens/onboarding_screen_test.dart; git commit -m "refactor(onboarding): drop the sign-in page - auth moved to the launch LoginScreen"
```

---

### Task 5: Wire the gate in `main.dart`

**Files:**
- Modify: `lib/main.dart`

**Interfaces:**
- Consumes: `LaunchHome` / `resolveLaunchHome` (Task 1),
  `AppSettings.guestChosen` (Task 2), `LoginScreen(onAdvance:)` (Task 3),
  `OnboardingScreen(onDone:)` (unchanged, Task 4).
- Produces: `_RiseAppState` resolves `LaunchHome` in `initState` and after
  `LoginScreen.onAdvance`. No new public API.

Note: there is intentionally no widget test pumping `RiseApp` — its `home`
needs an `AlarmRepository` (heavy to fake) and the decision itself is fully
covered by the pure tests in Task 1 plus the screen tests in Tasks 3-4.
`flutter analyze` and the device smoke test cover the wiring.

- [ ] **Step 1: Add the imports**

In `lib/main.dart`, add `import 'domain/launch_gate.dart';` next to the other
`domain/` import, and `import 'ui/screens/login_screen.dart';` next to the
other `ui/screens/` imports.

- [ ] **Step 2: Replace the field and initState resolution**

Replace `late bool _showOnboarding;` with:

```dart
  /// The launch-gate decision, resolved once in [initState] and re-resolved
  /// after LoginScreen reports an advance (sign-in or guest). See
  /// [_resolveHome].
  late LaunchHome _home;
```

In `initState`, replace

```dart
    _showOnboarding =
        widget.settings != null && !widget.settings!.onboardingComplete;
```

with `_home = _resolveHome();`

- [ ] **Step 3: Add `_resolveHome` and `_advanceFromLogin`**

Directly above `_completeOnboarding`, add:

```dart
  /// The one launch-gate decision. All inputs are synchronous: settings were
  /// loaded before runApp, and the auth service primes its account
  /// synchronously from the restored session at construction — so `current`
  /// is the known truth on the first frame and a signed-in user can never
  /// see LoginScreen ("loading is never signed-out"). A settings failure
  /// treats onboarding as complete (never traps) and guest as unchosen.
  LaunchHome _resolveHome() {
    final settings = widget.settings;
    return resolveLaunchHome(
      repositoryReady: widget.repository != null,
      authConfigured: SupabaseConfig.isConfigured,
      signedIn: ref.read(authServiceProvider).current != null,
      guestChosen: settings?.guestChosen ?? false,
      onboardingComplete: settings?.onboardingComplete ?? true,
    );
  }

  /// LoginScreen completed (sign-in or guest). Re-resolve with the new truth
  /// and swap home in place — the same pattern as [_completeOnboarding].
  void _advanceFromLogin() => setState(() => _home = _resolveHome());
```

- [ ] **Step 4: Swap the `home` ternary for the four-way switch**

In `build`, delete the now-unused `final repository = widget.repository;`
local, and replace the `home:` argument with:

```dart
      home: KeyedSubtree(
        key: _homeKey,
        child: switch (_home) {
          LaunchHome.startupFailed => const _StartupFailedPage(),
          LaunchHome.login => LoginScreen(onAdvance: _advanceFromLogin),
          LaunchHome.onboarding =>
            OnboardingScreen(onDone: _completeOnboarding),
          LaunchHome.shell => const AppShell(),
        },
      ),
```

- [ ] **Step 5: Verify and commit**

Run: `flutter analyze` — expect clean (this also catches any leftover
`_showOnboarding` reference). Run the touched test files as a regression check:

```powershell
flutter test test/domain/launch_gate_test.dart test/ui/screens/login_screen_test.dart test/ui/screens/onboarding_screen_test.dart
```

Expected: PASS. Then:

```powershell
git add lib/main.dart; git commit -m "feat(launch): three-way gate - login first, then onboarding for everyone, then the shell"
```

---

### Task 6: `MissionPreviewScreen` (the sandbox host)

**Files:**
- Create: `lib/ui/missions/mission_preview_screen.dart`
- Test: `test/ui/missions/mission_preview_screen_test.dart`

**Interfaces:**
- Consumes: `MissionBuilder` typedef from `lib/ui/screens/ring_screen.dart`;
  `buildMission` from `lib/ui/missions/mission_host.dart`; `kMissionLabels` /
  `kDifficultyMissions` from `lib/ui/components/mission_picker_sheet.dart`.
- Produces:

```dart
class MissionPreviewScreen extends StatefulWidget {
  const MissionPreviewScreen({
    super.key,
    required this.alarm,
    required this.locked,
    required this.onOpenPaywall,
    this.missionBuilder = buildMission,
  });
  final Alarm alarm;          // the sandbox mission config (count is always 1)
  final bool locked;          // premium-gated for this user right now
  final VoidCallback onOpenPaywall;
  final MissionBuilder missionBuilder; // injected in tests
}
```

Task 8 consumes this verbatim.

- [ ] **Step 1: Write the failing test**

Create `test/ui/missions/mission_preview_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/alarm.dart';
import 'package:rise/ui/missions/mission_preview_screen.dart';

/// A hermetic stand-in for a real mission widget: shows which mission it got
/// and offers a one-tap solve.
Widget _fakeMission(BuildContext context, Alarm alarm, VoidCallback onSolved,
        void Function(int)? onAlertness) =>
    Column(mainAxisSize: MainAxisSize.min, children: [
      Text('SANDBOX ${alarm.mission}'),
      TextButton(onPressed: onSolved, child: const Text('solve')),
    ]);

Future<void> _push(WidgetTester t, MissionPreviewScreen screen) async {
  await t.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => screen)),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('hosts the mission and shows the preview chrome', (t) async {
    await _push(
      t,
      MissionPreviewScreen(
        alarm: const Alarm(id: 1, hour: 6, minute: 30, mission: 'tap'),
        locked: false,
        onOpenPaywall: () {},
        missionBuilder: _fakeMission,
      ),
    );
    expect(find.text('PREVIEW'), findsOneWidget);
    expect(find.text('Tap'), findsOneWidget);
    expect(find.text('SANDBOX tap'), findsOneWidget);
  });

  testWidgets('solving a free mission shows the completion card and Back pops',
      (t) async {
    await _push(
      t,
      MissionPreviewScreen(
        alarm: const Alarm(
            id: 1, hour: 6, minute: 30, mission: 'tap', missionDiff: 'medium'),
        locked: false,
        onOpenPaywall: () {},
        missionBuilder: _fakeMission,
      ),
    );
    await t.tap(find.text('solve'));
    await t.pumpAndSettle();

    expect(find.text('Solved — that\'s Tap on Medium.'), findsOneWidget);
    expect(find.text('See Premium'), findsNothing);

    await t.tap(find.text('Back to missions'));
    await t.pumpAndSettle();
    expect(find.text('open'), findsOneWidget); // back off the route
  });

  testWidgets('solving a locked premium mission shows the upsell; See Premium '
      'fires the paywall callback', (t) async {
    var paywalls = 0;
    await _push(
      t,
      MissionPreviewScreen(
        alarm: const Alarm(id: 1, hour: 6, minute: 30, mission: 'typing'),
        locked: true,
        onOpenPaywall: () => paywalls++,
        missionBuilder: _fakeMission,
      ),
    );
    await t.tap(find.text('solve'));
    await t.pumpAndSettle();

    expect(find.text('Solved — that\'s Type a phrase on Easy.'), findsOneWidget);
    expect(find.text('Unlock Premium to wake with Type a phrase.'),
        findsOneWidget);
    expect(find.text('Back to missions'), findsOneWidget);

    await t.tap(find.text('See Premium'));
    await t.pump();
    expect(paywalls, 1);
  });

  testWidgets('the difficulty clause is omitted for missions that take none',
      (t) async {
    await _push(
      t,
      MissionPreviewScreen(
        alarm: const Alarm(id: 1, hour: 6, minute: 30, mission: 'qr'),
        locked: true,
        onOpenPaywall: () {},
        missionBuilder: _fakeMission,
      ),
    );
    await t.tap(find.text('solve'));
    await t.pumpAndSettle();
    expect(find.text('Solved — that\'s Scan a code.'), findsOneWidget);
  });

  testWidgets('End preview pops without solving', (t) async {
    await _push(
      t,
      MissionPreviewScreen(
        alarm: const Alarm(id: 1, hour: 6, minute: 30, mission: 'math'),
        locked: false,
        onOpenPaywall: () {},
        missionBuilder: _fakeMission,
      ),
    );
    await t.tap(find.byKey(const Key('end-preview')));
    await t.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(find.text('SANDBOX math'), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/missions/mission_preview_screen_test.dart`
Expected: FAIL — "Target of URI doesn't exist:
'package:rise/ui/missions/mission_preview_screen.dart'".

- [ ] **Step 3: Write minimal implementation**

Create `lib/ui/missions/mission_preview_screen.dart`:

```dart
import 'package:flutter/material.dart';

import '../../domain/alarm.dart';
import '../components/mission_picker_sheet.dart'
    show kDifficultyMissions, kMissionLabels;
import '../components/rise_buttons.dart';
import '../screens/ring_screen.dart' show MissionBuilder;
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'mission_host.dart';

/// A sandbox for trying a wake mission from the picker — deliberately NOT a
/// RingScreen: no alarm audio, no snooze, no wake recording, no platform
/// alarm calls (the alarm path is sacred, and nothing here is a real firing).
/// The mission itself runs its real widget via [missionBuilder] so what the
/// user feels is exactly what a morning would feel like. Pushed as a route
/// over the open picker sheet, so popping returns to the sheet exactly as it
/// was left — scroll, selection and config all preserved by the Navigator.
class MissionPreviewScreen extends StatefulWidget {
  const MissionPreviewScreen({
    super.key,
    required this.alarm,
    required this.locked,
    required this.onOpenPaywall,
    this.missionBuilder = buildMission,
  });

  /// The sandbox mission config. The picker always passes count 1: a preview
  /// demonstrates the mechanic, not the endurance of a chain.
  final Alarm alarm;

  /// Whether this mission is premium-gated for the current user. A locked
  /// mission is fully playable (try-before-you-buy); solving it ends with an
  /// upsell card instead of a plain completion.
  final bool locked;

  final VoidCallback onOpenPaywall;

  /// Injected in tests (a hermetic fake); production runs the real host.
  final MissionBuilder missionBuilder;

  @override
  State<MissionPreviewScreen> createState() => _MissionPreviewScreenState();
}

class _MissionPreviewScreenState extends State<MissionPreviewScreen> {
  bool _solved = false;

  String get _label => kMissionLabels[widget.alarm.mission] ?? 'Mission';

  void _onSolved() => setState(() => _solved = true);

  String _cap(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RiseColors.appBg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(RiseSpacing.screen, 8, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('PREVIEW',
                            style: RiseText.sectionLabel
                                .copyWith(color: RiseColors.textFaint)),
                        Text(_label, style: RiseText.title),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const Key('end-preview'),
                    tooltip: 'End preview',
                    icon: Icon(Icons.close, color: RiseColors.textDim),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(RiseSpacing.screen),
                  child: _solved
                      ? _solvedCard()
                      : widget.missionBuilder(
                          context, widget.alarm, _onSolved, null),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The post-solve card. A free (or entitled) mission ends plainly; a locked
  /// premium mission ends with the teaser upsell — the user felt the mission,
  /// now they can buy it. "Back to missions" always just pops to the picker.
  Widget _solvedCard() {
    final diff = kDifficultyMissions.contains(widget.alarm.mission)
        ? ' on ${_cap(widget.alarm.missionDiff)}'
        : '';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: RiseColors.accentSoft,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Icon(Icons.check_rounded,
              size: 36, color: RiseColors.positive),
        ),
        const SizedBox(height: 20),
        Text('Solved — that\'s $_label$diff.',
            textAlign: TextAlign.center, style: RiseText.title),
        if (widget.locked) ...[
          const SizedBox(height: 10),
          Text('Unlock Premium to wake with $_label.',
              textAlign: TextAlign.center,
              style: RiseText.body.copyWith(color: RiseColors.textDim)),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(
              label: 'See Premium',
              icon: Icons.star_outline,
              onPressed: widget.onOpenPaywall,
            ),
          ),
          const SizedBox(height: 6),
          GhostButton(
            label: 'Back to missions',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ] else ...[
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(
              label: 'Back to missions',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ],
      ],
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/missions/mission_preview_screen_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

Run `flutter analyze` — expect clean. Then:

```powershell
git add lib/ui/missions/mission_preview_screen.dart test/ui/missions/mission_preview_screen_test.dart; git commit -m "feat(missions): MissionPreviewScreen - sandbox try-out with premium teaser upsell"
```

---

### Task 7: Per-row Preview in the mission picker

**Files:**
- Modify: `lib/ui/components/mission_picker_sheet.dart`
- Test: `test/ui/components/mission_picker_sheet_test.dart`

**Interfaces:**
- Consumes: nothing from earlier tasks (Task 8 wires `MissionPreviewScreen`).
- Produces: `showMissionPickerSheet` and `MissionPickerSheet` gain a required
  `void Function(Alarm preview) onPreview` parameter (after `onRegisterPhoto`).
  The preview alarm contract: `mission` = the row's key, `missionDiff` =
  the picker's current difficulty, `missionCount` = 1 always, `missionData`
  kept only when previewing the currently selected `qr`/`photo` mission.
  Task 8 depends on this signature verbatim.

- [ ] **Step 1: Write the failing tests**

In `test/ui/components/mission_picker_sheet_test.dart`, update the `_sheet`
helper to accept and forward `onPreview`:

```dart
MissionPickerSheet _sheet({
  required Alarm initial,
  bool missionsLocked = false,
  bool chainsLocked = false,
  VoidCallback? onOpenPaywall,
  Future<String?> Function()? onRegisterQr,
  Future<String?> Function()? onRegisterPhoto,
  void Function(Alarm)? onPreview,
  ValueChanged<Alarm>? onConfirm,
  VoidCallback? onCancel,
}) {
  return MissionPickerSheet(
    initial: initial,
    missionsLocked: missionsLocked,
    chainsLocked: chainsLocked,
    onOpenPaywall: onOpenPaywall ?? () {},
    onRegisterQr: onRegisterQr ?? () async => null,
    onRegisterPhoto: onRegisterPhoto ?? () async => null,
    onPreview: onPreview ?? (_) {},
    onConfirm: onConfirm ?? (_) {},
    onCancel: onCancel ?? () {},
  );
}
```

Append these tests inside `main()`:

```dart
  testWidgets('every mission row except None offers Preview', (t) async {
    await _pump(t, _sheet(initial: const Alarm(id: 1, hour: 6, minute: 30)));
    // 12 missions, 11 previews: 'none' is just slide-to-wake — nothing to try.
    expect(find.text('Preview'), findsNWidgets(11));
    expect(find.byKey(const Key('preview-None')), findsNothing);
  });

  testWidgets('Preview synthesises the row mission at count 1 without touching '
      'the draft', (t) async {
    final previews = <Alarm>[];
    Alarm? confirmed;
    await _pump(
      t,
      _sheet(
        initial: const Alarm(
            id: 1, hour: 6, minute: 30, mission: 'math', missionDiff: 'medium'),
        onPreview: previews.add,
        onConfirm: (a) => confirmed = a,
      ),
    );
    // Set a chain length and difficulty in the sheet, then preview a
    // DIFFERENT row (Shake it off).
    await t.tap(find.text('3×'));
    await t.pump();
    await t.tap(find.text('Hard'));
    await t.pump();
    await t.tap(find.byKey(const Key('preview-Shake it off')));
    await t.pump();

    expect(previews, hasLength(1));
    final p = previews.single;
    expect(p.mission, 'shake');
    expect(p.missionCount, 1, reason: 'a preview demonstrates the mechanic');
    expect(p.missionDiff, 'hard', reason: 'the picker\'s current difficulty');
    expect(p.missionData, isNull);

    // The draft is untouched: Done still returns math / hard / 3×.
    await t.tap(find.text('Done'));
    await t.pump();
    expect(confirmed!.mission, 'math');
    expect(confirmed!.missionDiff, 'hard');
    expect(confirmed!.missionCount, 3);
  });

  testWidgets('Preview keeps a registration only for the selected qr/photo '
      'mission', (t) async {
    final previews = <Alarm>[];
    await _pump(
      t,
      _sheet(
        initial: const Alarm(
            id: 1, hour: 6, minute: 30, mission: 'qr', missionData: 'CODE-123'),
        onPreview: previews.add,
      ),
    );
    // Selected qr row: the registration rides along so the try-out is real.
    await t.tap(find.byKey(const Key('preview-Scan a code')));
    await t.pump();
    expect(previews.single.mission, 'qr');
    expect(previews.single.missionData, 'CODE-123');

    // A different registration-based row must NOT inherit it.
    await t.tap(find.byKey(const Key('preview-Snap a spot')));
    await t.pump();
    expect(previews.last.mission, 'photo');
    expect(previews.last.missionData, isNull,
        reason: 'a QR payload can never masquerade as a photo hash');
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/components/mission_picker_sheet_test.dart`
Expected: FAIL — "no named parameter with the name 'onPreview'".

- [ ] **Step 3: Implement the per-row Preview**

In `lib/ui/components/mission_picker_sheet.dart`:

1. `showMissionPickerSheet`: add `required void Function(Alarm preview) onPreview,`
   after `onRegisterPhoto`, and forward it in the `MissionPickerSheet(...)`
   constructor call. Add this bullet to the doc comment:

```dart
/// - [onPreview] receives a sandbox alarm for a row's Preview button (the
///   row's mission, current difficulty, count 1); the caller pushes a preview
///   route over the sheet so returning preserves the sheet's exact state.
```

2. `MissionPickerSheet`: add the constructor parameter
   `required this.onPreview,` and the field:

```dart
  /// Receives the sandbox alarm for a row's Preview button. Injected (like
  /// the paywall/register callbacks) so the sheet stays Navigator-free.
  final void Function(Alarm preview) onPreview;
```

3. In `_MissionPickerSheetState`, add after `_selectMission`:

```dart
  /// Builds the sandbox alarm for a row's Preview button: the row's mission
  /// at the current difficulty, always a single round (a preview demonstrates
  /// the mechanic, not the endurance). A QR/photo registration rides along
  /// only when previewing the mission it belongs to — a QR payload must never
  /// masquerade as a photo hash. The sheet's [_draft] is never mutated:
  /// previewing is look-don't-touch.
  Alarm _previewFor(String key) {
    final keepRegistration =
        key == _draft.mission && (key == 'qr' || key == 'photo');
    return _draft.copyWith(
      mission: key,
      missionCount: 1,
      clearMissionData: !keepRegistration,
    );
  }
```

4. In the `ListView` tile builder, pass:

```dart
                _MissionTile(
                  label: kMissionLabels[key]!,
                  description: kMissionDescriptions[key] ?? '',
                  selected: key == mission,
                  locked: _isLocked(key),
                  onTap: () => _selectMission(key),
                  // 'none' is just slide-to-wake — nothing to try.
                  onPreview:
                      key == 'none' ? null : () => widget.onPreview(_previewFor(key)),
                ),
```

5. `_MissionTile`: add `this.onPreview` to the constructor and
   `final VoidCallback? onPreview;` to the fields, then render the button in
   the trailing `Row`, immediately before the `if (locked) ...` block:

```dart
            if (onPreview != null)
              GestureDetector(
                key: Key('preview-$label'),
                behavior: HitTestBehavior.opaque,
                onTap: onPreview,
                child: Container(
                  constraints:
                      const BoxConstraints(minWidth: 44, minHeight: 44),
                  alignment: Alignment.center,
                  margin: const EdgeInsets.only(right: 2),
                  child: Text(
                    'Preview',
                    style: RiseText.caption.copyWith(
                        color: RiseColors.accent, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/components/mission_picker_sheet_test.dart`
Expected: PASS (all old + new tests).

- [ ] **Step 5: Commit**

Run `flutter analyze` — expect clean. Then:

```powershell
git add lib/ui/components/mission_picker_sheet.dart test/ui/components/mission_picker_sheet_test.dart; git commit -m "feat(picker): per-row Preview button with look-don't-touch sandbox alarm"
```

---

### Task 8: Wire preview from Create/Edit + round-trip test

**Files:**
- Modify: `lib/ui/screens/create_edit_screen.dart`
- Test: `test/ui/components/mission_picker_sheet_test.dart` (round-trip test
  appended)

**Interfaces:**
- Consumes: `MissionPreviewScreen` (Task 6) and the picker's `onPreview`
  contract (Task 7); existing `openPaywall(context)` and
  `isPremiumMissionKey`.
- Produces: a pushed `MissionPreviewScreen` route above the open sheet.

- [ ] **Step 1: Write the failing round-trip test**

Append to `test/ui/components/mission_picker_sheet_test.dart`, inside
`main()`:

```dart
  testWidgets('preview pushes over the sheet and returns to the exact state '
      '(scroll + selection preserved)', (t) async {
    t.view.physicalSize = const Size(1200, 2400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    Alarm? result;
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await showMissionPickerSheet(
                context,
                draft: const Alarm(id: 1, hour: 6, minute: 30),
                missionsLocked: false,
                chainsLocked: false,
                onOpenPaywall: () {},
                onRegisterQr: () async => null,
                onRegisterPhoto: () async => null,
                // Mirrors Create/Edit: push the preview over the open sheet
                // using the OUTER context, then pop to return.
                onPreview: (preview) => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (previewContext) => Scaffold(
                      body: TextButton(
                        onPressed: () =>
                            Navigator.of(previewContext).maybePop(),
                        child: Text('close preview ${preview.mission}'),
                      ),
                    ),
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('Wake mission'), findsOneWidget);

    // Select Math, then scroll all the way to the last mission.
    await t.tap(find.text('Math'));
    await t.pump();
    await t.scrollUntilVisible(find.text('Keep your eyes open'), 300,
        scrollable: find.byType(Scrollable).first);
    await t.pump();

    // Preview it and come back.
    await t.tap(find.byKey(const Key('preview-Keep your eyes open')));
    await t.pumpAndSettle();
    expect(find.text('close preview eyes'), findsOneWidget);
    await t.tap(find.text('close preview eyes'));
    await t.pumpAndSettle();

    // Exact place: the last row is still on stage (scroll preserved)...
    expect(find.text('Keep your eyes open'), findsOneWidget);
    // ...and the Math selection survived — Done returns it.
    await t.tap(find.text('Done'));
    await t.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.mission, 'math');
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/components/mission_picker_sheet_test.dart`
Expected: FAIL — "no named parameter with the name 'onPreview'" on
`showMissionPickerSheet`. (If Task 7 already added it to the public helper,
this test passes immediately — that's fine; it is the wiring contract Task 8
must keep green.)

- [ ] **Step 3: Wire `onPreview` in Create/Edit**

In `lib/ui/screens/create_edit_screen.dart`, add the import:

```dart
import '../missions/mission_preview_screen.dart';
```

In `_openMissionPicker`, add the `onPreview` argument to the
`showMissionPickerSheet(...)` call, directly after `onRegisterPhoto`:

```dart
      onPreview: (preview) {
        // Push the sandbox OVER the open sheet (this context belongs to
        // Create/Edit, which sits under the sheet route in the same
        // navigator), so popping the preview returns to the picker exactly
        // as it was left. Premium missions are previewable — the teaser
        // upsell after a solve is the conversion path, and `locked` drives it.
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => MissionPreviewScreen(
            alarm: preview,
            locked:
                isPremiumMissionKey(preview.mission) && missionsLocked,
            onOpenPaywall: () => openPaywall(context),
          ),
        ));
      },
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/ui/components/mission_picker_sheet_test.dart test/ui/screens/create_edit_screen_test.dart`
Expected: PASS (including the round-trip test; existing Create/Edit tests
unaffected — Preview only fires when tapped).

- [ ] **Step 5: Commit**

Run `flutter analyze` — expect clean. Then:

```powershell
git add lib/ui/screens/create_edit_screen.dart test/ui/components/mission_picker_sheet_test.dart; git commit -m "feat(picker): wire Preview from Create/Edit - sandbox pushes over the sheet, pop returns to exact state"
```

---

### Task 9: Full verification + STATUS.md

**Files:**
- Modify: `STATUS.md`

- [ ] **Step 1: Run the whole suite**

Run: `flutter test`
Expected: all 1222 existing tests + ~20 new tests PASS (2 old onboarding
sign-in tests were replaced in Task 4).

Run: `flutter analyze`
Expected: "No issues found!".

- [ ] **Step 2: Update STATUS.md**

STATUS.md keeps ONE H1 that names the latest ship. Replace the current first
line (`# Rise — Status (round-3 structural redesign, 2026-07-26)`) with:

```markdown
# Rise — Status (login-first flow + mission preview, 2026-08-04)
```

Replace the existing `**Verified:**` line (lines 3-5) with:

```markdown
**Verified:** `flutter analyze` clean · full test suite green.
```

Insert the following section immediately BEFORE the existing
`## Shipped 2026-07-26, round 3 — the structural redesign` heading:

```markdown
## Shipped 2026-08-04 — login-first launch flow + mission preview

- **Login is the front door.** When auth is configured and the user is known
  signed-out with no guest choice on record, the app opens on a new
  LoginScreen: Sign in with Google or Continue as guest. The guest choice is
  remembered (`AppSettings.guestChosen`) and never re-asked; signing in clears
  it, so a sign-out returns to login. The gate is a pure synchronous decision
  (`lib/domain/launch_gate.dart`) fed by `AuthService.current` — a signed-in
  user can never see login flash. Unconfigured auth skips login entirely.
- **Onboarding is now a pure tour.** The sign-in page is gone; everyone —
  signed-in or guest — gets the same six pages after the login screen.
- **Every mission row has Preview.** The picker's rows (all but None) run the
  real mission in a new sandbox `MissionPreviewScreen` pushed over the open
  sheet — scroll, selection, difficulty and registrations are exactly as left
  on return. Premium missions are playable and end with an upsell card;
  selecting them still goes through the paywall. Nothing is recorded.

### Needs you

1. **Device smoke test (fresh install):** cold start → LoginScreen; guest →
   onboarding → shell; kill app → cold start goes straight to the shell (no
   login). Sign in from Profile, sign out, cold start → LoginScreen again.
2. **Preview round-trip:** Create/Edit → Wake mission → scroll, pick a
   difficulty, Preview Shake/QR/Math → solve → Back to missions → confirm the
   sheet is exactly where you left it. Solve a premium mission → upsell shows.
3. No new migrations, no backend changes, no new packages.
```

(Everything below the insertion point — the round-3 sections and the rest of
the file — stays as-is.)

- [ ] **Step 3: Commit**

```powershell
git add STATUS.md; git commit -m "docs: STATUS - login-first flow + mission preview shipped"
```

---

## Self-Review Checklist (run after the plan is complete)

- Spec §1 (gate) → Tasks 1, 2, 5. §2 (LoginScreen) → Task 3. §3 (onboarding) →
  Task 4. §4 (preview) → Tasks 6, 7, 8. §5 (edge cases) → code in Tasks 3
  (never-trap prefs, error toast), 6 (locked upsell, end-preview), 7
  (registration hygiene). §6 (testing) → per-task tests + Task 9.
- Type consistency: `resolveLaunchHome` / `LaunchHome` (1→5);
  `setGuestChosen` / `guestChosen` (2→3,5); `LoginScreen(onAdvance:)` (3→5);
  `onPreview` signature `void Function(Alarm)` (7→8); `MissionPreviewScreen`
  ctor (6→8). All match.
