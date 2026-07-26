# Social UX Overhaul Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Kill the signed-out flash and per-visit spinners, and rework Crew / Group-detail / Stats / Profile into calm, deduplicated, hierarchy-first screens.

**Architecture:** Prime `SupabaseAuthService` synchronously from the restored Supabase session plus a SharedPreferences `ProfileCache`; make social providers non-autoDispose, account-keyed, and warmed at shell level; render skeleton placeholders (never sign-in / never empty-state) while truth is unknown; merge Group-detail's three member lists into one; regroup Stats and Profile.

**Tech Stack:** Flutter, Riverpod 2.6.1 (pinned), supabase_flutter, shared_preferences. No new dependencies.

## Global Constraints

- Riverpod stays pinned at 2.6.1; no new packages.
- Light theme pixels outside the four target screens must not change.
- `RiseSpinner` remains for in-button busy states only; content loading uses skeletons.
- All copy stays in the app's warm, non-judgemental voice.
- Existing test suite (~1048 tests) stays green; `flutter analyze` stays clean.
- Reduced motion (`MediaQueryData.disableAnimations`) must disable skeleton pulse and entrance animations.

---

### Task 1: ProfileCache

**Files:**
- Create: `lib/data/auth/profile_cache.dart`
- Test: `test/data/auth/profile_cache_test.dart`

**Interfaces:**
- Produces: `class ProfileCache { ProfileCache(SharedPreferences prefs); RiseAccount? read(String userId); Future<void> write(RiseAccount account); Future<void> clear(); }`

- [ ] **Step 1: Write the failing tests** — round-trip write/read, id-mismatch returns null, clear removes, corrupt JSON returns null, null-username account round-trips (username stays null).

```dart
// test/data/auth/profile_cache_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/auth/profile_cache.dart';
import 'package:rise/domain/rise_account.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const account = RiseAccount(
      id: 'u1', username: 'ada', displayName: 'Ada L.',
      avatarColor: '#7C9CF4', email: 'ada@example.com');

  Future<ProfileCache> cache() async {
    SharedPreferences.setMockInitialValues(const {});
    return ProfileCache(await SharedPreferences.getInstance());
  }

  test('write then read round-trips the account', () async {
    final c = await cache();
    await c.write(account);
    expect(c.read('u1'), account);
  });

  test('read for a different user id returns null', () async {
    final c = await cache();
    await c.write(account);
    expect(c.read('someone-else'), isNull);
  });

  test('clear removes the cached profile', () async {
    final c = await cache();
    await c.write(account);
    await c.clear();
    expect(c.read('u1'), isNull);
  });

  test('corrupt stored JSON reads as null, never throws', () async {
    SharedPreferences.setMockInitialValues({'cachedProfile': '{not json'});
    final c = ProfileCache(await SharedPreferences.getInstance());
    expect(c.read('u1'), isNull);
  });

  test('an unclaimed (null username) account round-trips', () async {
    final c = await cache();
    await c.write(const RiseAccount(
        id: 'u2', displayName: 'New', avatarColor: '#7C9CF4'));
    expect(c.read('u2')!.needsUsername, isTrue);
  });
}
```

- [ ] **Step 2: Run to verify failure** — `flutter test test/data/auth/profile_cache_test.dart` → FAIL (no such file).
- [ ] **Step 3: Implement**

```dart
// lib/data/auth/profile_cache.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/rise_account.dart';

/// Last-known signed-in profile, persisted so a relaunch can render the
/// account instantly (no "signed out" flash, no claim-gate flash) while the
/// live profiles row is re-fetched. One profile per install: written on every
/// successful profile fetch, cleared on sign-out/delete.
class ProfileCache {
  ProfileCache(this._prefs);
  final SharedPreferences _prefs;
  static const _key = 'cachedProfile';

  /// The cached account, or null when absent, corrupt, or for another user.
  RiseAccount? read(String userId) {
    final raw = _prefs.getString(_key);
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (map['id'] != userId) return null;
      return RiseAccount(
        id: map['id'] as String,
        username: map['username'] as String?,
        displayName: (map['displayName'] as String?) ?? '',
        avatarColor: (map['avatarColor'] as String?) ?? '#7C9CF4',
        email: map['email'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> write(RiseAccount account) => _prefs.setString(
        _key,
        jsonEncode({
          'id': account.id,
          'username': account.username,
          'displayName': account.displayName,
          'avatarColor': account.avatarColor,
          'email': account.email,
        }),
      );

  Future<void> clear() => _prefs.remove(_key);
}
```

- [ ] **Step 4: Run tests** → PASS. **Step 5: Commit** `feat(auth): ProfileCache for instant account hydration`.

### Task 2: Synchronous auth priming

**Files:**
- Modify: `lib/data/auth/supabase_auth_service.dart`
- Modify: `lib/ui/state/auth_providers.dart` (add `profileCacheProvider`)
- Modify: `lib/main.dart` (build prefs once; override provider)
- Test: `test/data/auth/supabase_auth_service_test.dart` (new — pure priming helper)

**Interfaces:**
- Consumes: `ProfileCache` (Task 1).
- Produces: `({RiseAccount? account, bool primed}) primeFromSession(User? user, ProfileCache? cache)` (top-level, `@visibleForTesting`); `SupabaseAuthService({SupabaseClient? client, String? serverClientId, ProfileCache? cache})`; `final profileCacheProvider = Provider<ProfileCache?>((_) => null);` overridden in `main.dart`.

- [ ] **Step 1: Failing tests** for `primeFromSession`: null user → primed null; user + matching cache → primed cached account; user + no/mismatched cache → not primed, account null.
- [ ] **Step 2: Implement.** In the service: constructor takes `this._cache`, calls `primeFromSession(_client.auth.currentSession?.user, _cache)` and sets `_current`/`_primed` BEFORE subscribing to `onAuthStateChange`. `account()` becomes:

```dart
@override
Stream<RiseAccount?> account() async* {
  if (_primed) yield _current;   // session truth known now — emit immediately
  yield* _accounts.stream;       // not primed → stay AsyncLoading until fetch
}
```

Listener body sets `_primed = true` before emitting. `_accountForUser` writes the cache after a *successful* fetch (`fetchFailed == false`), best-effort try/catch; the `signedOut` branch (user == null) and `signOut()` both `await _cache?.clear()` best-effort. `auth_providers.dart`: `authServiceProvider` passes `cache: ref.watch(profileCacheProvider)`. `main.dart`: `final prefs = await SharedPreferences.getInstance(); settings = AppSettings(prefs);` and add `profileCacheProvider.overrideWithValue(ProfileCache(prefs))` to the ProviderScope overrides (guard: only when prefs loaded; keep the existing try/catch shape).
- [ ] **Step 3: Tests pass; `flutter analyze` clean; commit** `fix(auth): prime account synchronously from restored session + cache — no signed-out flash`.

### Task 3: Provider retention + account keying + warmup host

**Files:**
- Modify: `lib/ui/state/feed_providers.dart`, `lib/ui/state/voice_providers.dart`, `lib/ui/state/group_providers.dart` (`myGroupsProvider`), `lib/ui/state/leaderboard_providers.dart`
- Create: `lib/ui/social_warmup_host.dart`
- Modify: `lib/ui/screens/app_shell.dart` (mount host in the host stack)
- Test: `test/ui/state/feed_providers_test.dart` (create), extend `test/ui/state/voice_providers_test.dart`, `test/ui/social_warmup_host_test.dart` (create)

**Interfaces:**
- Produces: same provider names, now plain `FutureProvider` (no autoDispose), each first line `ref.watch(accountProvider.select((a) => a.value?.id));`; `class SocialWarmupHost extends ConsumerWidget { const SocialWarmupHost({super.key, required this.child}); }`.

- [ ] **Step 1: Failing provider tests**: (a) feed data survives removing the only listener (read again → same instance, no second service call); (b) account-id change re-runs the fetch (service called again); (c) warmup host: pumping it signed-in initializes `crewFeedProvider` (fake feed service records a call) without any Crew screen.
- [ ] **Step 2: Implement.** Warmup host mirrors the existing `*Host` widgets:

```dart
// lib/ui/social_warmup_host.dart
class SocialWarmupHost extends ConsumerWidget {
  const SocialWarmupHost({super.key, required this.child});
  final Widget child;

  static void _noop(Object? _, Object? __) {}

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(accountProvider.select((a) => a.value != null));
    if (signedIn) {
      ref.listen(crewProvider, _noop);
      ref.listen(crewStatusesProvider, _noop);
      ref.listen(crewFeedProvider, _noop);
      ref.listen(myGroupsProvider, _noop);
      ref.listen(voiceInboxProvider, _noop);
      ref.listen(leaderboardProvider, _noop);
    }
    return child;
  }
}
```

Mount inside `AppShell.build`'s host stack (innermost, above `FeedPublisherHost`'s child).
- [ ] **Step 3: Tests pass; commit** `perf(social): retained, account-keyed social caches + shell warmup (no per-visit refetch)`.

### Task 4: RiseSkeleton component

**Files:**
- Create: `lib/ui/components/rise_skeleton.dart`
- Test: `test/ui/components/rise_skeleton_test.dart`

**Interfaces:**
- Produces: `class RiseSkeleton extends StatefulWidget { const RiseSkeleton({super.key, this.width, required this.height, this.radius = RiseRadii.sm}); }` (a `surface2` rounded block pulsing opacity 0.55→1.0, 900ms reverse-repeat; static at 0.75 under reduced motion) and `class RiseSkeletonCircle extends StatelessWidget { const RiseSkeletonCircle({super.key, required this.size}); }`.

- [ ] Failing test: renders with fixed size; reduced motion (`MediaQueryData(disableAnimations: true)`) → no `AnimationController` ticking (pump 2s, no pending timers). Implement, pass, commit `feat(ui): RiseSkeleton loading placeholders`.

### Task 5: Crew screen loading truth + pull-to-refresh

**Files:**
- Modify: `lib/ui/screens/crew_screen.dart`, `lib/ui/screens/groups_tab.dart`
- Test: extend `test/ui/screens/crew_screen_test.dart`, `test/ui/screens/groups_tab_test.dart`

- [ ] **Step 1: Failing widget tests**: (a) auth restoring (never-emitting `AuthService` double) → no "Sign in with Google", no "Wake up together", skeletons present (`find.byType(RiseSkeletonCircle)`); (b) crew stream pending → skeleton strip, NOT "Mornings are better with a crew"; (c) feed pending → skeleton rows, no `RiseSpinner`; (d) `RefreshIndicator` present when signed in.
- [ ] **Step 2: Implement.** Build gate:

```dart
final accountAsync = ref.watch(accountProvider);
final account = accountAsync.value;
if (account == null) {
  if (accountAsync.isLoading) return const _CrewRestoringSkeleton();
  final configured = ref.watch(authServiceProvider) is! DisabledAuthService;
  return _CrewSignedOut(configured: configured);
}
final crewAsync = ref.watch(crewProvider);
final crewLoading = crewAsync.isLoading && !crewAsync.hasValue;
final crew = crewAsync.value ?? CrewState.empty;
```

Strip: `crewLoading` → `_MorningStripSkeleton` (SectionLabel + 4 × circle-52 + 40×10 bar); else existing hasCrew/empty branches. Feed `loading:` → two skeleton rows (circle 38 + two bars) replacing the spinner. GroupsTab `loading:` → two `RiseSkeleton(width: 150, height: kCrewGroupCardHeight, radius: RiseRadii.base)`. Wrap the signed-in `ListView` in `RefreshIndicator(color: RiseColors.primary, backgroundColor: RiseColors.card, onRefresh: ...)` invalidating feed/groups/voice then awaiting their `.future`s with errors swallowed. `initState` post-frame: invalidate each of feed/groups/voice **only if** `ref.read(p).hasValue` (stale-while-revalidate; Riverpod keeps previous data so no flicker). `_CrewRestoringSkeleton` = SafeArea + padded column: title row skeleton, then the strip skeleton.
- [ ] **Step 3: All crew tests pass; commit** `fix(crew): skeletons over spinners, truthful loading states, pull-to-refresh`.

### Task 6: Profile — account skeleton + grouped lists

**Files:**
- Modify: `lib/ui/screens/profile_screen.dart`
- Test: extend `test/ui/screens/profile_screen_test.dart`

- [ ] **Step 1: Failing tests**: (a) restoring auth → no "Sign in to Riserys" and a skeleton (find.byType(RiseSkeleton)); (b) grouped card: "Settings" and "How you've been feeling" inside one `RiseCard`; (c) signed-in: "Sign out" and "Delete account" present in one card, delete styled danger.
- [ ] **Step 2: Implement.** `_AccountSectionState.build` tri-state (skeleton = card with circle-52 + two bars). New private `_GroupedCard(rows)` helper: one `RiseCard` with `Divider(height: 20, color: RiseColors.divider)` between rows; rows keep their keys/onTaps. Groups: [Settings, Wellbeing check-in]; Reliability section: [Setup Guardian] card then `PermissionsSection` unchanged; account actions: one grouped card [Sign out, Delete account(text-only danger row)]. Premium entry and About unchanged.
- [ ] **Step 3: Pass; commit** `refactor(profile): grouped sections + account skeleton (no sign-in flash)`.

### Task 7: Group detail — one member list

**Files:**
- Create: `lib/domain/group_roster.dart`
- Modify: `lib/ui/screens/group_detail_screen.dart`
- Test: create `test/domain/group_roster_test.dart`, rework `test/ui/screens/group_detail_screen_test.dart`

**Interfaces:**
- Produces: `class RosterEntry { final CrewMember member; final CrewStanding? standing; final int? rank; }` and `List<RosterEntry> mergeRoster(List<CrewStanding> standings, List<CrewMember> members)` — standings order first (rank 1..n, joined to the member by id; a standing with no roster row still renders from its own fields), then remaining members alphabetically with `rank == null`.

- [ ] **Step 1: Failing unit tests** for `mergeRoster`: ranks follow standings order; roster-only members append unranked alphabetically; standing-only ids still included; join by id (not username).
- [ ] **Step 2: Failing widget tests**: each member renders exactly once (e.g. `find.text('@ada')` findsOneWidget); owner sees per-row "…" overflow with "Remove from group" (old always-visible Remove pill gone); race live → 🔥/💤 chips inside the member rows and "Day N · M still standing" inside the score card; no race + owner → "Start a streak race"; separate "Members" and "Group leaderboard" section pair no longer both listing people (single section label "Members" — leaderboard label removed).
- [ ] **Step 3: Implement.** Screen structure: header → compact invite row → score card (with race status line + owner End-race ghost when live) → race CTA card (only when no race) → single "Members" section (merged rows: rank `#`, `CrewAvatar`, name + `@handle · X% on time`/`no wakes yet`, race chip when live, streak column when standing exists, Owner badge, owner-only "…" overflow → `showCrewSheet` with danger "Remove from group" → existing `_removeMember`) → footer leave/delete. Skeleton rows (3 × row of circle+bars) while `members`/`board` first-load, `RiseSpinner` gone.
- [ ] **Step 4: Pass; commit** `refactor(groups): merge leaderboard/roster/race into one member list — no duplicates`.

### Task 8: Stats — hierarchy + compact actions + leaderboard skeleton

**Files:**
- Modify: `lib/ui/screens/stats_screen.dart`
- Test: extend `test/ui/screens/stats_screen_test.dart`

- [ ] **Step 1: Failing tests**: (a) "Rough night?" and "Share your progress" render side-by-side (same `Row` ancestor); (b) section order streak → Overview → "Your mornings" → Consistency → Alertness → patterns → Achievements → leaderboard (assert via widget y-positions of section labels); (c) leaderboard loading → skeleton rows, no spinner; (d) single "Alertness" section label (old "Alertness trend" label gone).
- [ ] **Step 2: Implement.** New `_ActionTile` (compact: icon, title, one-line caption, tappable, optional busy spinner slot) used by Rough-night and Share (Share keeps its offscreen `RepaintBoundary` Stack + premium lock). Reorder the ListView children per spec; "Your mornings" section = 30-day calendar + week chart + consistency caption line; Consistency card follows; Alertness = card + trend content + `RiseDisclaimer` under one label. Leaderboard `loading:` → 3 skeleton standing-rows.
- [ ] **Step 3: Pass; commit** `refactor(stats): narrative hierarchy, compact action pair, leaderboard skeleton`.

### Task 9: Full verification + review + merge

- [ ] `flutter analyze` → 0 issues.
- [ ] `flutter test` → all green (expect ~1048 + new).
- [ ] `flutter build apk --debug` succeeds.
- [ ] Dispatch code-review subagent over `git diff main...HEAD`; fix findings; re-run tests.
- [ ] Merge branch to `main` (user's established finish state), update `STATUS.md` user-action checklist (device smoke test steps).
