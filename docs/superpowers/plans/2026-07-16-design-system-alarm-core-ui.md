# Rise Plan 3: Design System + Alarm-Core UI — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the throwaway dev screens with the real shadcn-style "Mono" UI from the prototype — a design system plus the alarm-core screens (Onboarding, Home, Create/Edit, Ringing, the four dismiss missions, Profile/Settings) — wired to the alarm engine from Plans 1–2.

**Architecture:** A token-driven Flutter design system (colors, Geist/Geist Mono typography, radii, shadows, spacing as compile-time constants) plus focused reusable widgets, composed into screens. A Riverpod (2.x) state layer sits over the existing `AlarmRepository`/`AlarmSyncService` so screens read and edit alarms without touching persistence directly; every write reconciles the platform scheduler. The ringing screen replaces `DevRingPage` and is launched by the same native `getRingingAlarmId` poll `main.dart` already uses. This is pure Flutter — it builds and is testable on Windows for Android, and the identical code compiles for iOS later (the ring screen is the one place with a platform nuance: on iOS 26 AlarmKit renders its own alert, so the Flutter ring screen is the Android/pre-26 path).

**Tech Stack:** Flutter 3.35.1 / Dart 3.9.0 · flutter_riverpod ^2.6.1 (2.x API — 3.x conflicts with `drift_dev`) · Drift (existing) · bundled Geist + Geist Mono fonts · widget + golden tests.

**Verification:** Every widget and screen is testable on Windows via `flutter test` (widget tests) and golden tests. The final task wires `main.dart` and verifies the full flow on the Android emulator and the user's Samsung, exactly as Plan 1 Task 12 did. No device is needed until then.

**Out of scope (later plans):** Crew / Groups / friend detail / voice alarms (Plans 5–6); Sleep stats / leaderboard (Plan 7); the advanced reliability layer — snooze budget, wake-up check, escalation ladder, goal-lock, mission chaining, and the Photo/QR/Typing/Shake missions (Plan 4); real authentication (Plan 5 — onboarding's sign-in is a placeholder that proceeds); premium/paywall (Plan 8); dark "midnight" theme (deferred). The Crew and Sleep tabs render a simple "coming soon" placeholder.

## Global Constraints

Design tokens copied verbatim from `docs/superpowers/specs/2026-07-15-rise-alarm-app-design.md` and `project/Rise.dc.html` (the "Mono" theme — the only theme in v1). Every task's requirements implicitly include this section.

**Color (hex):** app bg `#f4f4f5` · card/surface `#ffffff` · surface-2 `#fafafa` · text `#09090b` · text-dim `#71717a` · text-faint `#a1a1aa` · border `#e4e4e7` · divider `#f0f0f1` · primary `#18181b` · primary-text `#fafafa` · accent `#18181b` · accent-soft `#f4f4f5` · danger `#ef4444` · positive `#22c55e` · waking `#f59e0b`. Friend avatar colors (used later): Maya `#f43f5e`, Sana `#8b5cf6`, Leo `#3b82f6`, Ivy `#f59e0b`, Kojo `#10b981`.

**Typography:** Geist for UI/display (display/titles weight 600, letter-spacing −0.02em); Geist Mono for all numerals/times/stats (weight 300–600). Section labels: 11px, weight 600, letter-spacing 0.1em, UPPERCASE, text-dim. Body 14–15px; captions 12–13px. **Minimum hit target 44px.**

**Radius:** sm 9 · base 13 · lg 18 · pill 999. **Card shadow:** `0 1px 2px rgba(24,24,27,.05), 0 1px 3px rgba(24,24,27,.04)`. **Primary shadow:** `0 1px 2px rgba(0,0,0,.10)`. **Spacing:** screen padding 20 · card padding 13–16 · gaps 10–12.

**Animations to keep** (from the prototype): bell-swing, glow/ring pulse, waveform, pop-in, sheet-up (create/mission slide in from bottom, `.32s cubic-bezier(.2,.8,.2,1)`), toast-up, status-dot pulse. Respect the platform reduced-motion setting.

**Behavior:** switches/toggles animate translateX 0↔18px over 0.2s; toasts auto-hide ~2.7s; the time picker supports both chevrons and vertical pointer-drag (~7px per step, values wrap); slide-to-wake uses pointer capture, fill and knob track the drag, snap back if released < 97%; missions use random on-screen positions (`x: 6–72%`, `y: 18–70%`).

**Domain / state:** the local DB is the source of truth; every alarm write goes through `AlarmSyncService.reconcileNow()` so the platform scheduler stays in sync. `flutter_riverpod` is **2.x** — use `StateNotifierProvider`/`Provider`/`ConsumerWidget`, not 3.x codegen. Day indices 0=Sun…6=Sat; time stored 24-hour.

**Launch gate for this plan (final task):** the real Home → Create → save → Ring → dismiss flow works on the Android emulator and the physical Samsung, replacing the dev screens.

---

## File structure

```
lib/ui/
  theme/
    tokens.dart          RiseColors, RiseRadii, RiseShadows, RiseSpacing (const)
    typography.dart      RiseText — Geist/Geist Mono TextStyles + the type scale
  components/
    rise_card.dart       RiseCard (surface + border + card shadow)
    rise_buttons.dart    PrimaryButton, SecondaryButton, GhostButton
    section_label.dart   SectionLabel (11px uppercase 0.1em)
    rise_switch.dart     RiseSwitch (animated toggle)
    segmented.dart       SegmentedControl<T>
    day_chips.dart       DayChips (S M T W T F S) + repeatLabel()
    sound_chips.dart     SoundChips
    status_dot.dart      StatusDot (asleep/waking/awake) — used by later plans
    toast.dart           ToastHost + RiseToast
    time_dial.dart       TimeDial (draggable HH:MM + chevrons + AM/PM)
    slide_to_wake.dart   SlideToWake (draggable knob track)
  screens/
    onboarding_screen.dart
    home_screen.dart
    create_edit_screen.dart
    ring_screen.dart          replaces DevRingPage
    profile_screen.dart
    missions/
      mission_host.dart       launches the right overlay for an alarm's mission
      math_mission.dart
      hold_mission.dart
      tap_mission.dart
      memory_mission.dart
  shell/
    app_shell.dart            tab scaffold (Home / Crew* / +FAB / Sleep* / You)
  state/
    alarm_providers.dart      Riverpod providers over AlarmRepository/AlarmSyncService
lib/domain/alarm.dart         + mission, missionDiff fields
lib/data/local/database.dart  + mission, missionDiff columns, schemaVersion 2 migration
assets/fonts/                 Geist + Geist Mono TTFs
lib/main.dart                 wire AppShell + real RingScreen (replace dev screens)
```

The dev screens (`lib/ui/dev_home_page.dart`, `lib/ui/dev_ring_page.dart`) are deleted in the final task once the real screens replace them.

---

## Task group A — design-system foundation (widget/golden tests on Windows)

### Task 1: Design tokens

**Files:**
- Create: `lib/ui/theme/tokens.dart`
- Test: `test/ui/tokens_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `class RiseColors` — static `const Color` for every token: `appBg`, `card`, `surface2`, `text`, `textDim`, `textFaint`, `border`, `divider`, `primary`, `primaryText`, `accent`, `accentSoft`, `danger`, `positive`, `waking`.
  - `class RiseRadii` — static `const double sm = 9, base = 13, lg = 18, pill = 999`.
  - `class RiseShadows` — `static const List<BoxShadow> card`, `static const List<BoxShadow> primary`.
  - `class RiseSpacing` — `static const double screen = 20, cardPad = 14, gap = 11`.

- [ ] **Step 1: Write the failing test**

Create `test/ui/tokens_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/ui/theme/tokens.dart';

void main() {
  test('core colors match the Mono spec hex values', () {
    expect(RiseColors.appBg, const Color(0xFFF4F4F5));
    expect(RiseColors.card, const Color(0xFFFFFFFF));
    expect(RiseColors.text, const Color(0xFF09090B));
    expect(RiseColors.textDim, const Color(0xFF71717A));
    expect(RiseColors.primary, const Color(0xFF18181B));
    expect(RiseColors.primaryText, const Color(0xFFFAFAFA));
    expect(RiseColors.danger, const Color(0xFFEF4444));
    expect(RiseColors.positive, const Color(0xFF22C55E));
    expect(RiseColors.waking, const Color(0xFFF59E0B));
  });

  test('radii match the spec', () {
    expect(RiseRadii.sm, 9);
    expect(RiseRadii.base, 13);
    expect(RiseRadii.lg, 18);
    expect(RiseRadii.pill, 999);
  });

  test('card shadow is the two-layer spec shadow', () {
    expect(RiseShadows.card, hasLength(2));
    expect(RiseShadows.card.first.blurRadius, 2);
    expect(RiseShadows.card.last.blurRadius, 3);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/ui/tokens_test.dart
```
Expected: FAIL — `tokens.dart` not found.

- [ ] **Step 3: Write the implementation**

Create `lib/ui/theme/tokens.dart`:

```dart
import 'package:flutter/widgets.dart';

/// The "Mono" theme — the only theme in v1. Values are the exact hex from the
/// design spec; do not adjust them without updating the spec.
abstract final class RiseColors {
  static const appBg = Color(0xFFF4F4F5);
  static const card = Color(0xFFFFFFFF);
  static const surface2 = Color(0xFFFAFAFA);
  static const text = Color(0xFF09090B);
  static const textDim = Color(0xFF71717A);
  static const textFaint = Color(0xFFA1A1AA);
  static const border = Color(0xFFE4E4E7);
  static const divider = Color(0xFFF0F0F1);
  static const primary = Color(0xFF18181B);
  static const primaryText = Color(0xFFFAFAFA);
  static const accent = Color(0xFF18181B);
  static const accentSoft = Color(0xFFF4F4F5);
  static const danger = Color(0xFFEF4444);
  static const positive = Color(0xFF22C55E);
  static const waking = Color(0xFFF59E0B);
}

abstract final class RiseRadii {
  static const double sm = 9;
  static const double base = 13;
  static const double lg = 18;
  static const double pill = 999;
}

abstract final class RiseShadows {
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x0D18181B), offset: Offset(0, 1), blurRadius: 2),
    BoxShadow(color: Color(0x0A18181B), offset: Offset(0, 1), blurRadius: 3),
  ];
  static const List<BoxShadow> primary = [
    BoxShadow(color: Color(0x1A000000), offset: Offset(0, 1), blurRadius: 2),
  ];
}

abstract final class RiseSpacing {
  static const double screen = 20;
  static const double cardPad = 14;
  static const double gap = 11;
}
```

> `0x0D18181B` = `rgba(24,24,27,.05)` (alpha 0.05 ≈ 0x0D); `0x0A18181B` = `.04` ≈ 0x0A; `0x1A000000` = `rgba(0,0,0,.10)` ≈ 0x1A. These are the spec's card and primary shadows.

- [ ] **Step 4: Run the test to verify it passes**

```bash
flutter test test/ui/tokens_test.dart
```
Expected: PASS — 3 tests green.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/theme/tokens.dart test/ui/tokens_test.dart
git commit -m "feat(ui): add Mono design tokens"
```

---

### Task 2: Typography + bundled Geist fonts

**Files:**
- Create: `assets/fonts/` (Geist + Geist Mono TTFs)
- Modify: `pubspec.yaml` (font declarations)
- Create: `lib/ui/theme/typography.dart`
- Test: `test/ui/typography_test.dart`

**Interfaces:**
- Consumes: `RiseColors` (Task 1).
- Produces:
  - `class RiseText` — static `TextStyle` getters: `display` (Geist 600, −0.02em), `title` (Geist 600), `body` (Geist 400, 14.5), `caption` (Geist 400, 12.5, textDim), `sectionLabel` (Geist 600, 11, +0.1em spacing, uppercase caller responsibility), `mono({double size, FontWeight weight, Color color})` (Geist Mono), and `monoDisplay` (Geist Mono 500, large — for the ring clock).
  - Font families registered as `'Geist'` and `'Geist Mono'`.

- [ ] **Step 1: Bundle the font files**

Geist and Geist Mono are open-source (OFL, by Vercel). Download the static TTFs into `assets/fonts/`. From the repo root:

```bash
mkdir -p assets/fonts
# Geist: weights 400,500,600,700 ; Geist Mono: 300,400,500,600
# Source: https://github.com/vercel/geist-font (static/ TTFs) or Google Fonts.
# Download these exact files into assets/fonts/:
#   Geist-Regular.ttf Geist-Medium.ttf Geist-SemiBold.ttf Geist-Bold.ttf
#   GeistMono-Light.ttf GeistMono-Regular.ttf GeistMono-Medium.ttf GeistMono-SemiBold.ttf
ls assets/fonts/
```
Expected: the 8 TTF files listed. (If a download tool is unavailable, fetch them from https://fonts.google.com/specimen/Geist and https://fonts.google.com/specimen/Geist+Mono, which provide the static TTFs.)

- [ ] **Step 2: Declare the fonts in pubspec.yaml**

Under `flutter:` in `pubspec.yaml`, add:

```yaml
  fonts:
    - family: Geist
      fonts:
        - asset: assets/fonts/Geist-Regular.ttf
          weight: 400
        - asset: assets/fonts/Geist-Medium.ttf
          weight: 500
        - asset: assets/fonts/Geist-SemiBold.ttf
          weight: 600
        - asset: assets/fonts/Geist-Bold.ttf
          weight: 700
    - family: Geist Mono
      fonts:
        - asset: assets/fonts/GeistMono-Light.ttf
          weight: 300
        - asset: assets/fonts/GeistMono-Regular.ttf
          weight: 400
        - asset: assets/fonts/GeistMono-Medium.ttf
          weight: 500
        - asset: assets/fonts/GeistMono-SemiBold.ttf
          weight: 600
```

Run `flutter pub get`.

- [ ] **Step 3: Write the failing test**

Create `test/ui/typography_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/ui/theme/tokens.dart';
import 'package:rise/ui/theme/typography.dart';

void main() {
  test('display uses Geist 600 with tight tracking', () {
    final s = RiseText.display;
    expect(s.fontFamily, 'Geist');
    expect(s.fontWeight, FontWeight.w600);
    expect(s.letterSpacing, closeTo(-0.02 * (s.fontSize ?? 0), 0.5));
  });

  test('mono uses Geist Mono and honors overrides', () {
    final s = RiseText.mono(size: 46, weight: FontWeight.w500, color: RiseColors.text);
    expect(s.fontFamily, 'Geist Mono');
    expect(s.fontSize, 46);
    expect(s.fontWeight, FontWeight.w500);
    expect(s.color, RiseColors.text);
  });

  test('section label is 11px semibold with wide tracking', () {
    final s = RiseText.sectionLabel;
    expect(s.fontSize, 11);
    expect(s.fontWeight, FontWeight.w600);
    expect(s.letterSpacing, closeTo(1.1, 0.2)); // ~0.1em of 11px
    expect(s.color, RiseColors.textDim);
  });
}
```

- [ ] **Step 4: Run the test to verify it fails**

```bash
flutter test test/ui/typography_test.dart
```
Expected: FAIL — `typography.dart` not found.

- [ ] **Step 5: Write the implementation**

Create `lib/ui/theme/typography.dart`:

```dart
import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// The Mono type scale. Geist for UI/display, Geist Mono for every numeral,
/// time and stat — the monospace numerals are the design's signature.
abstract final class RiseText {
  static const _ui = 'Geist';
  static const _mono = 'Geist Mono';

  static const TextStyle display = TextStyle(
    fontFamily: _ui,
    fontWeight: FontWeight.w600,
    fontSize: 26,
    height: 1.1,
    letterSpacing: -0.02 * 26,
    color: RiseColors.text,
  );

  static const TextStyle title = TextStyle(
    fontFamily: _ui,
    fontWeight: FontWeight.w600,
    fontSize: 16,
    letterSpacing: -0.01 * 16,
    color: RiseColors.text,
  );

  static const TextStyle body = TextStyle(
    fontFamily: _ui,
    fontWeight: FontWeight.w400,
    fontSize: 14.5,
    color: RiseColors.text,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: _ui,
    fontWeight: FontWeight.w400,
    fontSize: 12.5,
    color: RiseColors.textDim,
  );

  /// 11px uppercase semibold with 0.1em tracking. Callers uppercase the text.
  static const TextStyle sectionLabel = TextStyle(
    fontFamily: _ui,
    fontWeight: FontWeight.w600,
    fontSize: 11,
    letterSpacing: 1.1,
    color: RiseColors.textDim,
  );

  static TextStyle mono({
    double size = 15,
    FontWeight weight = FontWeight.w500,
    Color color = RiseColors.text,
    double? letterSpacing,
  }) =>
      TextStyle(
        fontFamily: _mono,
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
      );
}
```

- [ ] **Step 6: Run the test to verify it passes**

```bash
flutter test test/ui/typography_test.dart
```
Expected: PASS — 3 tests green.

- [ ] **Step 7: Commit**

```bash
git add assets/fonts/ pubspec.yaml lib/ui/theme/typography.dart test/ui/typography_test.dart
git commit -m "feat(ui): bundle Geist fonts and add the Mono type scale"
```

---
### Task 3: Static components — card, buttons, section label

**Files:**
- Create: `lib/ui/components/rise_card.dart`, `lib/ui/components/rise_buttons.dart`, `lib/ui/components/section_label.dart`
- Test: `test/ui/components/static_components_test.dart`

**Interfaces:**
- Consumes: `RiseColors`, `RiseRadii`, `RiseShadows`, `RiseSpacing`, `RiseText`.
- Produces:
  - `class RiseCard extends StatelessWidget` — `RiseCard({required Widget child, EdgeInsets? padding, double radius = RiseRadii.lg})`; white surface, 1px `border`, `RiseShadows.card`.
  - `class PrimaryButton extends StatelessWidget` — `PrimaryButton({required String label, required VoidCallback? onPressed, IconData? icon})`; `primary` bg, `primaryText`, `RiseShadows.primary`, radius base, 44px min height, disabled at 40% opacity when `onPressed == null`.
  - `class SecondaryButton extends StatelessWidget` — same shape, `card` bg + `border`, `text` label.
  - `class GhostButton extends StatelessWidget` — transparent, `accent` label (for "See all" / "New" style links).
  - `class SectionLabel extends StatelessWidget` — `SectionLabel(this.text)`; uppercases and applies `RiseText.sectionLabel`.

- [ ] **Step 1: Write the failing test**

Create `test/ui/components/static_components_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/ui/components/rise_buttons.dart';
import 'package:rise/ui/components/rise_card.dart';
import 'package:rise/ui/components/section_label.dart';
import 'package:rise/ui/theme/tokens.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('RiseCard renders its child', (t) async {
    await t.pumpWidget(_wrap(const RiseCard(child: Text('hello'))));
    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets('PrimaryButton fires onPressed', (t) async {
    var tapped = false;
    await t.pumpWidget(_wrap(PrimaryButton(label: 'Save', onPressed: () => tapped = true)));
    await t.tap(find.text('Save'));
    expect(tapped, isTrue);
  });

  testWidgets('PrimaryButton is disabled (no tap) when onPressed is null', (t) async {
    await t.pumpWidget(_wrap(const PrimaryButton(label: 'Save', onPressed: null)));
    await t.tap(find.text('Save'), warnIfMissed: false);
    // no callback to fire; assert it renders without throwing
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('PrimaryButton meets the 44px minimum hit target', (t) async {
    await t.pumpWidget(_wrap(PrimaryButton(label: 'Save', onPressed: () {})));
    final size = t.getSize(find.byType(PrimaryButton));
    expect(size.height, greaterThanOrEqualTo(44));
  });

  testWidgets('SectionLabel uppercases its text', (t) async {
    await t.pumpWidget(_wrap(const SectionLabel('your alarms')));
    expect(find.text('YOUR ALARMS'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/ui/components/static_components_test.dart
```
Expected: FAIL — component files not found.

- [ ] **Step 3: Write RiseCard**

Create `lib/ui/components/rise_card.dart`:

```dart
import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// White surface with a 1px border and the two-layer card shadow — the base
/// container for every card in the app.
class RiseCard extends StatelessWidget {
  const RiseCard({
    super.key,
    required this.child,
    this.padding,
    this.radius = RiseRadii.lg,
  });

  final Widget child;
  final EdgeInsets? padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(RiseSpacing.cardPad),
      decoration: BoxDecoration(
        color: RiseColors.card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: RiseColors.border),
        boxShadow: RiseShadows.card,
      ),
      child: child,
    );
  }
}
```

- [ ] **Step 4: Write the buttons**

Create `lib/ui/components/rise_buttons.dart`:

```dart
import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, required this.onPressed, this.icon});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return _BaseButton(
      onPressed: onPressed,
      background: RiseColors.primary,
      border: null,
      shadow: RiseShadows.primary,
      child: _content(label, icon, RiseColors.primaryText),
    );
  }
}

class SecondaryButton extends StatelessWidget {
  const SecondaryButton({super.key, required this.label, required this.onPressed, this.icon});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return _BaseButton(
      onPressed: onPressed,
      background: RiseColors.card,
      border: RiseColors.border,
      shadow: const [],
      child: _content(label, icon, RiseColors.text),
    );
  }
}

class GhostButton extends StatelessWidget {
  const GhostButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Text(label,
            style: RiseText.body.copyWith(
                color: RiseColors.accent, fontWeight: FontWeight.w600, fontSize: 13)),
      ),
    );
  }
}

Widget _content(String label, IconData? icon, Color color) {
  final text = Text(label,
      style: RiseText.body.copyWith(color: color, fontWeight: FontWeight.w600, fontSize: 15));
  if (icon == null) return text;
  return Row(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [Icon(icon, size: 16, color: color), const SizedBox(width: 8), text],
  );
}

class _BaseButton extends StatelessWidget {
  const _BaseButton({
    required this.onPressed,
    required this.background,
    required this.border,
    required this.shadow,
    required this.child,
  });

  final VoidCallback? onPressed;
  final Color background;
  final Color? border;
  final List<BoxShadow> shadow;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(RiseRadii.base),
            border: border == null ? null : Border.all(color: border!),
            boxShadow: shadow,
          ),
          child: child,
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Write SectionLabel**

Create `lib/ui/components/section_label.dart`:

```dart
import 'package:flutter/widgets.dart';

import '../theme/typography.dart';

/// 11px uppercase semibold label with 0.1em tracking, e.g. "YOUR ALARMS".
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: RiseText.sectionLabel);
}
```

- [ ] **Step 6: Run the test to verify it passes**

```bash
flutter test test/ui/components/static_components_test.dart
```
Expected: PASS — 5 tests green.

- [ ] **Step 7: Commit**

```bash
git add lib/ui/components/rise_card.dart lib/ui/components/rise_buttons.dart lib/ui/components/section_label.dart test/ui/components/static_components_test.dart
git commit -m "feat(ui): add card, buttons, and section label components"
```

---

### Task 4: Interactive chips — switch, segmented control, day chips, sound chips

**Files:**
- Create: `lib/ui/components/rise_switch.dart`, `lib/ui/components/segmented.dart`, `lib/ui/components/day_chips.dart`, `lib/ui/components/sound_chips.dart`
- Test: `test/ui/components/interactive_components_test.dart`

**Interfaces:**
- Consumes: tokens, typography.
- Produces:
  - `class RiseSwitch extends StatelessWidget` — `RiseSwitch({required bool value, required ValueChanged<bool> onChanged})`; 46×28 track, 22px knob, `translateX 0↔18` over 0.2s, on = `primary`, off = `border`.
  - `class SegmentedControl<T> extends StatelessWidget` — `SegmentedControl({required List<({T value, String label})> segments, required T selected, required ValueChanged<T> onChanged})`; selected = `primary` pill on `surface2` track.
  - `class DayChips extends StatelessWidget` — `DayChips({required Set<int> days, ValueChanged<int>? onToggle, bool compact = false})`; 7 chips S M T W T F S (index 0=Sun…6=Sat); active = `accentSoft` bg + `accent` text (compact/read-only) or `primary` (editable). Also `String repeatLabel(Set<int> days)` top-level function: "Once"/"Weekdays"/"Weekends"/"Every day"/comma list.
  - `class SoundChips extends StatelessWidget` — `SoundChips({required List<String> sounds, required String selected, required ValueChanged<String> onChanged})`; pill chips, selected = `primary`.

- [ ] **Step 1: Write the failing test**

Create `test/ui/components/interactive_components_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/ui/components/day_chips.dart';
import 'package:rise/ui/components/rise_switch.dart';
import 'package:rise/ui/components/segmented.dart';
import 'package:rise/ui/components/sound_chips.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('RiseSwitch toggles', (t) async {
    var v = false;
    await t.pumpWidget(_wrap(StatefulBuilder(builder: (c, setState) {
      return RiseSwitch(value: v, onChanged: (nv) => setState(() => v = nv));
    })));
    await t.tap(find.byType(RiseSwitch));
    await t.pumpAndSettle();
    expect(v, isTrue);
  });

  testWidgets('SegmentedControl reports the tapped value', (t) async {
    String? picked;
    await t.pumpWidget(_wrap(SegmentedControl<String>(
      segments: const [(value: 'a', label: 'Easy'), (value: 'b', label: 'Hard')],
      selected: 'a',
      onChanged: (v) => picked = v,
    )));
    await t.tap(find.text('Hard'));
    expect(picked, 'b');
  });

  testWidgets('DayChips toggles a day by index', (t) async {
    int? toggled;
    await t.pumpWidget(_wrap(DayChips(days: const {1, 2, 3, 4, 5}, onToggle: (i) => toggled = i)));
    // 7 letters S M T W T F S; tap the first (Sunday, index 0)
    await t.tap(find.text('S').first);
    expect(toggled, 0);
  });

  test('repeatLabel names common patterns', () {
    expect(repeatLabel(const {}), 'Once');
    expect(repeatLabel(const {1, 2, 3, 4, 5}), 'Weekdays');
    expect(repeatLabel(const {0, 6}), 'Weekends');
    expect(repeatLabel(const {0, 1, 2, 3, 4, 5, 6}), 'Every day');
    expect(repeatLabel(const {1, 3}), 'Mon, Wed');
  });

  testWidgets('SoundChips reports selection', (t) async {
    String? picked;
    await t.pumpWidget(_wrap(SoundChips(
      sounds: const ['Sunrise', 'Chimes'],
      selected: 'Sunrise',
      onChanged: (s) => picked = s,
    )));
    await t.tap(find.text('Chimes'));
    expect(picked, 'Chimes');
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/ui/components/interactive_components_test.dart
```
Expected: FAIL — component files not found.

- [ ] **Step 3: Write RiseSwitch**

Create `lib/ui/components/rise_switch.dart`:

```dart
import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

class RiseSwitch extends StatelessWidget {
  const RiseSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: Container(
        width: 46,
        height: 28,
        decoration: BoxDecoration(
          color: value ? RiseColors.primary : RiseColors.border,
          borderRadius: BorderRadius.circular(RiseRadii.pill),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 22,
            height: 22,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: const BoxDecoration(
              color: Color(0xFFFFFFFF),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 2, offset: Offset(0, 1))],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Write SegmentedControl**

Create `lib/ui/components/segmented.dart`:

```dart
import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

class SegmentedControl<T> extends StatelessWidget {
  const SegmentedControl({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  final List<({T value, String label})> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: RiseColors.surface2,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: RiseColors.border),
      ),
      child: Row(
        children: [
          for (final s in segments)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(s.value),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: s.value == selected ? RiseColors.primary : const Color(0x00000000),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    s.label,
                    style: RiseText.body.copyWith(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: s.value == selected ? RiseColors.primaryText : RiseColors.textDim,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Write DayChips + repeatLabel**

Create `lib/ui/components/day_chips.dart`:

```dart
import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

const _letters = ['S', 'M', 'T', 'W', 'T', 'F', 'S']; // index 0=Sun … 6=Sat
const _names = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

/// "Once" / "Weekdays" / "Weekends" / "Every day" / comma list.
String repeatLabel(Set<int> days) {
  if (days.isEmpty) return 'Once';
  final s = (days.toList()..sort()).join(',');
  if (s == '1,2,3,4,5') return 'Weekdays';
  if (s == '0,6') return 'Weekends';
  if (s == '0,1,2,3,4,5,6') return 'Every day';
  return (days.toList()..sort()).map((i) => _names[i]).join(', ');
}

class DayChips extends StatelessWidget {
  const DayChips({super.key, required this.days, this.onToggle, this.compact = false});

  final Set<int> days;
  final ValueChanged<int>? onToggle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 22.0 : 42.0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 0; i < 7; i++)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onToggle == null ? null : () => onToggle!(i),
            child: Container(
              width: compact ? size : null,
              height: size,
              constraints: compact ? null : const BoxConstraints(minWidth: 42),
              alignment: Alignment.center,
              margin: compact ? const EdgeInsets.only(right: 5) : null,
              padding: compact ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: days.contains(i)
                    ? (compact ? RiseColors.accentSoft : RiseColors.primary)
                    : (compact ? const Color(0x00000000) : RiseColors.surface2),
                borderRadius: BorderRadius.circular(compact ? 6 : 11),
              ),
              child: Text(
                _letters[i],
                style: (compact
                        ? RiseText.body.copyWith(fontSize: 10, fontWeight: FontWeight.w600)
                        : RiseText.body.copyWith(fontSize: 13, fontWeight: FontWeight.w600))
                    .copyWith(
                  color: days.contains(i)
                      ? (compact ? RiseColors.accent : RiseColors.primaryText)
                      : (compact ? RiseColors.textFaint : RiseColors.textDim),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
```

> Two weekday chips share the letter "T" (Tue, Thu) and two share "S" (Sun, Sat); the test taps `find.text('S').first` which is index 0 (Sunday). Rendering by index keeps toggling unambiguous even though letters repeat.

- [ ] **Step 6: Write SoundChips**

Create `lib/ui/components/sound_chips.dart`:

```dart
import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

class SoundChips extends StatelessWidget {
  const SoundChips({super.key, required this.sounds, required this.selected, required this.onChanged});

  final List<String> sounds;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in sounds)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(s),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
              decoration: BoxDecoration(
                color: s == selected ? RiseColors.primary : RiseColors.card,
                borderRadius: BorderRadius.circular(RiseRadii.pill),
                border: Border.all(color: s == selected ? const Color(0x00000000) : RiseColors.border),
              ),
              child: Text(
                s,
                style: RiseText.body.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: s == selected ? RiseColors.primaryText : RiseColors.text,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
```

- [ ] **Step 7: Run the test to verify it passes**

```bash
flutter test test/ui/components/interactive_components_test.dart
```
Expected: PASS — 5 tests green.

- [ ] **Step 8: Commit**

```bash
git add lib/ui/components/rise_switch.dart lib/ui/components/segmented.dart lib/ui/components/day_chips.dart lib/ui/components/sound_chips.dart test/ui/components/interactive_components_test.dart
git commit -m "feat(ui): add switch, segmented control, day chips, sound chips"
```

---
### Task 5: Interactions — TimeDial, SlideToWake, ToastHost

**Files:**
- Create: `lib/ui/components/time_dial.dart`, `lib/ui/components/slide_to_wake.dart`, `lib/ui/components/toast.dart`
- Test: `test/ui/components/interactions_test.dart`

**Interfaces:**
- Consumes: tokens, typography.
- Produces:
  - `typedef DialTime = ({int hour12, int minute, bool isAm});`
  - `class TimeDial extends StatelessWidget` — `TimeDial({required DialTime value, required ValueChanged<DialTime> onChanged})`. Drag a number vertically (~7px/step, wraps) or tap chevrons; AM/PM buttons.
  - `class SlideToWake extends StatefulWidget` — `SlideToWake({required VoidCallback onWake, String label = 'Slide to wake up'})`. Drag the knob; ≥97% fires `onWake` once; a shorter drag snaps back.
  - `class RiseToast extends StatelessWidget` — `RiseToast(String message)`; the pill visual.
  - `class ToastHost extends StatefulWidget` — `ToastHost({required String? message, required VoidCallback onHide, required Widget child})`; overlays `message` bottom-center and calls `onHide` ~2.7s later.

- [ ] **Step 1: Write the failing test**

Create `test/ui/components/interactions_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/ui/components/slide_to_wake.dart';
import 'package:rise/ui/components/time_dial.dart';
import 'package:rise/ui/components/toast.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  group('TimeDial', () {
    testWidgets('dragging the hour up increments it by ~7px/step', (t) async {
      DialTime v = (hour12: 6, minute: 30, isAm: true);
      await t.pumpWidget(_wrap(StatefulBuilder(
        builder: (c, s) => TimeDial(value: v, onChanged: (nv) => s(() => v = nv)),
      )));
      await t.drag(find.text('6'), const Offset(0, -21)); // 21px up = 3 steps
      await t.pump();
      expect(v.hour12, 9);
    });

    testWidgets('hour wraps 12 -> 1 when dragged past the top', (t) async {
      DialTime v = (hour12: 11, minute: 0, isAm: true);
      await t.pumpWidget(_wrap(StatefulBuilder(
        builder: (c, s) => TimeDial(value: v, onChanged: (nv) => s(() => v = nv)),
      )));
      await t.drag(find.text('11'), const Offset(0, -21)); // +3 -> 11,12,1 -> 2
      await t.pump();
      expect(v.hour12, 2);
    });

    testWidgets('AM/PM toggle reports the change', (t) async {
      DialTime v = (hour12: 6, minute: 30, isAm: true);
      await t.pumpWidget(_wrap(StatefulBuilder(
        builder: (c, s) => TimeDial(value: v, onChanged: (nv) => s(() => v = nv)),
      )));
      await t.tap(find.text('PM'));
      await t.pump();
      expect(v.isAm, isFalse);
    });
  });

  group('SlideToWake', () {
    testWidgets('sliding to the end fires onWake', (t) async {
      var woke = false;
      await t.pumpWidget(_wrap(SizedBox(width: 300, child: SlideToWake(onWake: () => woke = true))));
      await t.drag(find.byType(SlideToWake), const Offset(300, 0));
      expect(woke, isTrue);
    });

    testWidgets('a short slide snaps back and does not fire', (t) async {
      var woke = false;
      await t.pumpWidget(_wrap(SizedBox(width: 300, child: SlideToWake(onWake: () => woke = true))));
      await t.drag(find.byType(SlideToWake), const Offset(40, 0));
      await t.pumpAndSettle();
      expect(woke, isFalse);
    });
  });

  group('ToastHost', () {
    testWidgets('shows the message then hides it after ~2.7s', (t) async {
      var hidden = false;
      await t.pumpWidget(_wrap(SizedBox(
        width: 300, height: 300,
        child: ToastHost(message: 'Alarm set', onHide: () => hidden = true, child: const SizedBox()),
      )));
      await t.pump();
      expect(find.text('Alarm set'), findsOneWidget);
      await t.pump(const Duration(milliseconds: 2800));
      expect(hidden, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/ui/components/interactions_test.dart
```
Expected: FAIL — the three files not found.

- [ ] **Step 3: Write TimeDial**

Create `lib/ui/components/time_dial.dart`:

```dart
import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

/// The dial's current time: 12-hour clock plus AM/PM.
typedef DialTime = ({int hour12, int minute, bool isAm});

/// Big draggable HH:MM picker. Drag a number vertically (~7px per step) to
/// change it, or use the chevrons; values wrap. AM/PM buttons on the right.
class TimeDial extends StatelessWidget {
  const TimeDial({super.key, required this.value, required this.onChanged});

  final DialTime value;
  final ValueChanged<DialTime> onChanged;

  void _setHour(int h) => onChanged((hour12: h, minute: value.minute, isAm: value.isAm));
  void _setMinute(int m) => onChanged((hour12: value.hour12, minute: m, isAm: value.isAm));
  void _setAm(bool am) => onChanged((hour12: value.hour12, minute: value.minute, isAm: am));

  static int _wrapHour(int start, int step) => ((start - 1 + step) % 12 + 12) % 12 + 1;
  static int _wrapMinute(int start, int step) => ((start + step) % 60 + 60) % 60;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _DragNumber(
          value: value.hour12,
          format: (v) => '$v',
          wrap: _wrapHour,
          onChanged: _setHour,
          onIncrement: () => _setHour(value.hour12 % 12 + 1),
          onDecrement: () => _setHour(value.hour12 <= 1 ? 12 : value.hour12 - 1),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(':',
              style: RiseText.mono(size: 58, weight: FontWeight.w500, color: RiseColors.textFaint)),
        ),
        _DragNumber(
          value: value.minute,
          format: (v) => v.toString().padLeft(2, '0'),
          wrap: _wrapMinute,
          onChanged: _setMinute,
          onIncrement: () => _setMinute((value.minute + 1) % 60),
          onDecrement: () => _setMinute((value.minute + 59) % 60),
        ),
        const SizedBox(width: 8),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _AmPmButton(label: 'AM', selected: value.isAm, onTap: () => _setAm(true)),
            const SizedBox(height: 6),
            _AmPmButton(label: 'PM', selected: !value.isAm, onTap: () => _setAm(false)),
          ],
        ),
      ],
    );
  }
}

class _DragNumber extends StatefulWidget {
  const _DragNumber({
    required this.value,
    required this.format,
    required this.wrap,
    required this.onChanged,
    required this.onIncrement,
    required this.onDecrement,
  });

  final int value;
  final String Function(int) format;
  final int Function(int start, int step) wrap;
  final ValueChanged<int> onChanged;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  State<_DragNumber> createState() => _DragNumberState();
}

class _DragNumberState extends State<_DragNumber> {
  double _startY = 0;
  int _startValue = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _chevron(true, widget.onIncrement),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (d) {
            _startY = d.globalPosition.dy;
            _startValue = widget.value;
          },
          onVerticalDragUpdate: (d) {
            // Recompute from the drag start each move, like the prototype:
            // dragging up (smaller y) increases the value, ~7px per step.
            final step = ((_startY - d.globalPosition.dy) / 7).round();
            widget.onChanged(widget.wrap(_startValue, step));
          },
          child: SizedBox(
            width: 96,
            child: Text(
              widget.format(widget.value),
              textAlign: TextAlign.center,
              style: RiseText.mono(size: 66, weight: FontWeight.w500, color: RiseColors.text),
            ),
          ),
        ),
        _chevron(false, widget.onDecrement),
      ],
    );
  }

  Widget _chevron(bool up, VoidCallback onTap) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 44,
          height: 34,
          margin: const EdgeInsets.symmetric(vertical: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: RiseColors.surface2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: RiseColors.border),
          ),
          child: Icon(up ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              size: 18, color: RiseColors.textDim),
        ),
      );
}

class _AmPmButton extends StatelessWidget {
  const _AmPmButton({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? RiseColors.primary : RiseColors.surface2,
            borderRadius: BorderRadius.circular(11),
            border: selected ? null : Border.all(color: RiseColors.border),
          ),
          child: Text(label,
              style: RiseText.mono(
                  size: 15,
                  weight: FontWeight.w700,
                  color: selected ? RiseColors.primaryText : RiseColors.textDim)),
        ),
      );
}
```

> `find.text('6')` in the test hits the hour number. `t.drag` sends the offset as pointer moves; because `onVerticalDragUpdate` recomputes from `_startY` on each move, the final value reflects the total offset — 21px up = round(21/7) = 3 steps. Material `Icons` is why this file imports `flutter/material.dart` (the other components import only `flutter/widgets.dart`).

- [ ] **Step 4: Write SlideToWake**

Create `lib/ui/components/slide_to_wake.dart`:

```dart
import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Draggable "slide to wake up" track. The knob follows the drag; crossing 97%
/// of the travel fires [onWake] once. A shorter drag snaps the knob back.
class SlideToWake extends StatefulWidget {
  const SlideToWake({super.key, required this.onWake, this.label = 'Slide to wake up'});

  final VoidCallback onWake;
  final String label;

  @override
  State<SlideToWake> createState() => _SlideToWakeState();
}

class _SlideToWakeState extends State<SlideToWake> {
  static const double _trackHeight = 64;
  static const double _knob = 56;

  double _fraction = 0; // 0..1 of the available travel
  bool _fired = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final travel = (constraints.maxWidth - _knob).clamp(1.0, double.infinity);
        return GestureDetector(
          onHorizontalDragUpdate: (d) {
            if (_fired) return;
            setState(() => _fraction = (_fraction + d.delta.dx / travel).clamp(0.0, 1.0));
            if (_fraction >= 0.97) {
              _fired = true;
              widget.onWake();
            }
          },
          onHorizontalDragEnd: (_) {
            if (!_fired && _fraction < 0.97) setState(() => _fraction = 0);
          },
          child: Container(
            height: _trackHeight,
            decoration: BoxDecoration(
              color: RiseColors.card,
              borderRadius: BorderRadius.circular(RiseRadii.pill),
              border: Border.all(color: RiseColors.border),
            ),
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: _knob + _fraction * travel,
                  child: Container(
                    decoration: BoxDecoration(
                      color: RiseColors.accentSoft,
                      borderRadius: BorderRadius.circular(RiseRadii.pill),
                    ),
                  ),
                ),
                Center(
                  child: Text(widget.label,
                      style: RiseText.body.copyWith(
                          fontWeight: FontWeight.w600, color: RiseColors.textFaint)),
                ),
                Positioned(
                  left: 4 + _fraction * travel,
                  top: 4,
                  child: Container(
                    width: _knob,
                    height: _knob,
                    decoration: BoxDecoration(
                      color: RiseColors.primary,
                      shape: BoxShape.circle,
                      boxShadow: RiseShadows.primary,
                    ),
                    child: const Icon(Icons.arrow_forward, color: RiseColors.primaryText, size: 24),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 5: Write the toast**

Create `lib/ui/components/toast.dart`:

```dart
import 'dart:async';

import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

/// The dark pill toast visual.
class RiseToast extends StatelessWidget {
  const RiseToast(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 11),
      decoration: BoxDecoration(
        color: RiseColors.primary,
        borderRadius: BorderRadius.circular(RiseRadii.pill),
        boxShadow: const [
          BoxShadow(color: Color(0x47000000), offset: Offset(0, 8), blurRadius: 30),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(color: RiseColors.primaryText, shape: BoxShape.circle),
          ),
          const SizedBox(width: 9),
          Text(message,
              style: RiseText.body.copyWith(
                  fontSize: 13.5, fontWeight: FontWeight.w600, color: RiseColors.primaryText)),
        ],
      ),
    );
  }
}

/// Overlays [message] near the bottom of [child] and calls [onHide] ~2.7s after
/// it appears. The parent clears its message state in [onHide].
class ToastHost extends StatefulWidget {
  const ToastHost({
    super.key,
    required this.message,
    required this.onHide,
    required this.child,
  });

  final String? message;
  final VoidCallback onHide;
  final Widget child;

  @override
  State<ToastHost> createState() => _ToastHostState();
}

class _ToastHostState extends State<ToastHost> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.message != null) _arm();
  }

  @override
  void didUpdateWidget(ToastHost old) {
    super.didUpdateWidget(old);
    if (widget.message != null && widget.message != old.message) _arm();
  }

  void _arm() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 2700), () {
      if (mounted) widget.onHide();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (widget.message != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 104,
            child: Center(child: RiseToast(widget.message!)),
          ),
      ],
    );
  }
}
```

- [ ] **Step 6: Run the test to verify it passes**

```bash
flutter test test/ui/components/interactions_test.dart
```
Expected: PASS — all groups green.

> If the SlideToWake "end" test fails to fire: `t.drag` of the full width should push `_fraction` to 1.0 (≥0.97). If it snaps back instead, confirm `onWake` is called inside `onHorizontalDragUpdate` (not on end) so it fires the instant the threshold is crossed mid-drag.

- [ ] **Step 7: Run the whole suite and analyze**

```bash
flutter test
flutter analyze
```
Expected: all green; `No issues found!`.

- [ ] **Step 8: Commit**

```bash
git add lib/ui/components/time_dial.dart lib/ui/components/slide_to_wake.dart lib/ui/components/toast.dart test/ui/components/interactions_test.dart
git commit -m "feat(ui): add draggable time dial, slide-to-wake, and toast"
```

---

### Task 6: State layer + Alarm mission fields + DB migration

The one correctness-critical foundation task: it changes the database schema. Existing installs (the dev Samsung already has schemaVersion-1 data) must **upgrade**, not wipe — so this adds a real Drift 1→2 migration and tests it against a hand-built v1 database.

**Files:**
- Modify: `lib/domain/alarm.dart` (add `mission`, `missionDiff`)
- Modify: `lib/data/local/database.dart` (add columns, schemaVersion 2, migration)
- Modify: `lib/data/local/alarm_repository.dart` (map the new fields)
- Create: `lib/ui/state/alarm_providers.dart`
- Modify: `pubspec.yaml` (add `sqlite3` to dev_dependencies for the migration test)
- Test: `test/data/migration_test.dart`, `test/ui/state/alarm_providers_test.dart`
- Modify: `test/domain/alarm_test.dart` (extend for the new fields)

**Interfaces:**
- Consumes: `Alarm`, `AlarmRepository`, `AlarmSyncService` (Plans 1–2).
- Produces:
  - `Alarm` gains `String mission` (default `'none'`) and `String missionDiff` (default `'easy'`), in the constructor, `copyWith`, `==`, `hashCode`.
  - `RiseDatabase.schemaVersion == 2` with a `MigrationStrategy` that adds the two columns when upgrading from < 2.
  - `alarmSyncServiceProvider` (`Provider<AlarmSyncService>`), `alarmRepositoryProvider` (`Provider<AlarmRepository>`), `alarmsProvider` (`StreamProvider<List<Alarm>>`), `alarmMutationsProvider` (`Provider<AlarmMutations>` with `save`/`delete`/`setEnabled`, each reconciling), `draftProvider` (`StateNotifierProvider<DraftNotifier, Alarm?>`), `toastProvider` (`StateProvider<String?>`).

- [ ] **Step 1: Add mission fields to the Alarm entity**

In `lib/domain/alarm.dart`, add two constructor params (after `vibrate`), two fields, `copyWith` params, and include them in `==`/`hashCode`:

```dart
    this.vibrate = true,
    this.mission = 'none',
    this.missionDiff = 'easy',
    this.lastDismissedAt,
```
(insert `mission`/`missionDiff` before `lastDismissedAt` in the constructor). Fields (after `vibrate`):
```dart
  /// Dismiss mission: 'none' | 'math' | 'hold' | 'tap' | 'memory'.
  final String mission;

  /// Mission difficulty: 'easy' | 'medium' | 'hard'.
  final String missionDiff;
```
`copyWith` — add params and pass-throughs:
```dart
    String? mission,
    String? missionDiff,
```
and in the returned `Alarm(...)`: `mission: mission ?? this.mission, missionDiff: missionDiff ?? this.missionDiff,`.
`==` — add `&& other.mission == mission && other.missionDiff == missionDiff`.
`hashCode` — add `mission, missionDiff` to the `Object.hash(...)` argument list.

Add a test to `test/domain/alarm_test.dart`:
```dart
  test('mission fields default to none/easy and round-trip through copyWith', () {
    const a = Alarm(id: 1, hour: 6, minute: 30);
    expect(a.mission, 'none');
    expect(a.missionDiff, 'easy');
    final b = a.copyWith(mission: 'math', missionDiff: 'hard');
    expect(b.mission, 'math');
    expect(b.missionDiff, 'hard');
    expect(b.minute, 30); // unrelated field preserved
    expect(a == a.copyWith(), isTrue); // equality includes the new fields
  });
```

- [ ] **Step 2: Add the columns, schemaVersion 2, and the migration**

In `lib/data/local/database.dart`, add two columns to the `Alarms` table (after `lastDismissedAt`, before `customConstraints`):

```dart
  /// Dismiss mission and difficulty (added in schema v2).
  TextColumn get mission => text().withDefault(const Constant('none'))();
  TextColumn get missionDiff => text().withDefault(const Constant('easy'))();
```

Replace the `RiseDatabase` class with:

```dart
@DriftDatabase(tables: [Alarms])
class RiseDatabase extends _$RiseDatabase {
  RiseDatabase(super.e);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          // v1 -> v2: dismiss missions. Existing rows keep their data and get
          // the column defaults ('none'/'easy'); no wipe.
          if (from < 2) {
            await m.addColumn(alarms, alarms.mission);
            await m.addColumn(alarms, alarms.missionDiff);
          }
        },
      );
}
```

- [ ] **Step 3: Map the new fields in the repository**

In `lib/data/local/alarm_repository.dart`, `_toDomain` — add `mission: row.mission, missionDiff: row.missionDiff,` to the `Alarm(...)`. In `upsert`'s `AlarmsCompanion` — add `mission: Value(alarm.mission), missionDiff: Value(alarm.missionDiff),`.

- [ ] **Step 4: Regenerate Drift and run the entity/repository tests**

```bash
cd "C:/Users/ASUS/Desktop/startuping/rise"
dart run build_runner build --delete-conflicting-outputs
flutter test test/domain/alarm_test.dart test/data/alarm_repository_test.dart
```
Expected: `database.g.dart` regenerates with the two columns; entity and repository tests pass (the repository round-trips mission/missionDiff via the defaults; if the existing repository test asserts equality of a full Alarm, the new fields default on both sides so it stays green).

- [ ] **Step 5: Write the migration test**

Add `sqlite3` to `dev_dependencies` in `pubspec.yaml` (it is already present transitively; declaring it satisfies the analyzer for a direct import), then `flutter pub get`:

```yaml
dev_dependencies:
  sqlite3: ^2.4.0
```

Create `test/data/migration_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/local/database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('upgrading a v1 database adds mission columns and keeps existing rows', () async {
    // Build a schema-v1 alarms table by hand (no mission columns), as it
    // exists on an already-installed device, and seed one alarm.
    final raw = sqlite3.openInMemory();
    raw.execute('''
      CREATE TABLE alarms (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        hour INTEGER NOT NULL,
        minute INTEGER NOT NULL,
        days TEXT NOT NULL DEFAULT '',
        enabled INTEGER NOT NULL DEFAULT 1,
        label TEXT NOT NULL DEFAULT 'Alarm',
        sound_asset TEXT NOT NULL DEFAULT 'sounds/default_alarm.mp3',
        vibrate INTEGER NOT NULL DEFAULT 1,
        last_dismissed_at INTEGER,
        CHECK (hour BETWEEN 0 AND 23),
        CHECK (minute BETWEEN 0 AND 59)
      );
    ''');
    raw.execute("INSERT INTO alarms (hour, minute, label) VALUES (6, 30, 'Run');");
    raw.execute('PRAGMA user_version = 1;');

    // Opening RiseDatabase over this connection triggers onUpgrade(1 -> 2).
    final db = RiseDatabase(NativeDatabase.opened(raw));
    addTearDown(db.close);

    final rows = await db.select(db.alarms).get();
    expect(rows, hasLength(1), reason: 'existing row survives the upgrade');
    expect(rows.single.label, 'Run');
    expect(rows.single.mission, 'none', reason: 'new column defaults');
    expect(rows.single.missionDiff, 'easy');
    expect(await db.schemaVersion, 2);
  });

  test('a fresh database is created at v2 with the mission columns', () async {
    final db = RiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final id = await db.into(db.alarms).insert(
        AlarmsCompanion.insert(hour: 6, minute: 30));
    final row = await (db.select(db.alarms)..where((t) => t.id.equals(id))).getSingle();
    expect(row.mission, 'none');
    expect(row.missionDiff, 'easy');
  });
}
```

Run it:
```bash
flutter test test/data/migration_test.dart
```
Expected: PASS — both tests green. The first proves an existing v1 row upgrades (data intact, columns added with defaults); the second proves a fresh install is created at v2.

> If `NativeDatabase.opened` reports the DB is already at the target version and skips onUpgrade, confirm `PRAGMA user_version = 1` was set on `raw` before wrapping it. If `sqlite3.openInMemory` can't find the native library in the test runner, the existing `NativeDatabase.memory()` tests from Plan 1 prove sqlite loads here — use the same import setup they use.

- [ ] **Step 6: Write the Riverpod providers**

Create `lib/ui/state/alarm_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/alarm_sync_service.dart';
import '../../data/local/alarm_repository.dart';
import '../../domain/alarm.dart';

/// The app's configured AlarmSyncService. In production this is the singleton
/// built by `AlarmSyncService.configureForApp()` in main(); tests override it
/// with a service over an in-memory database.
final alarmSyncServiceProvider = Provider<AlarmSyncService>((ref) {
  return AlarmSyncService.instance;
});

final alarmRepositoryProvider = Provider<AlarmRepository>((ref) {
  return ref.watch(alarmSyncServiceProvider).repository;
});

/// Live list of the user's alarms from the local database.
final alarmsProvider = StreamProvider<List<Alarm>>((ref) {
  return ref.watch(alarmRepositoryProvider).watchAll();
});

/// Every alarm write persists locally AND re-arms the platform scheduler, so
/// the OS never drifts out of sync with the database (the source of truth).
class AlarmMutations {
  AlarmMutations(this._repo, this._sync);

  final AlarmRepository _repo;
  final AlarmSyncService _sync;

  Future<void> save(Alarm alarm) async {
    await _repo.upsert(alarm);
    await _sync.reconcileNow();
  }

  Future<void> delete(int id) async {
    await _repo.delete(id);
    await _sync.reconcileNow();
  }

  Future<void> setEnabled(int id, bool enabled) async {
    await _repo.setEnabled(id, enabled);
    await _sync.reconcileNow();
  }
}

final alarmMutationsProvider = Provider<AlarmMutations>((ref) {
  return AlarmMutations(ref.watch(alarmRepositoryProvider), ref.watch(alarmSyncServiceProvider));
});

/// The alarm currently being created or edited, or null when no form is open.
class DraftNotifier extends StateNotifier<Alarm?> {
  DraftNotifier() : super(null);

  void startNew() => state =
      const Alarm(id: 0, hour: 6, minute: 30, days: {1, 2, 3, 4, 5});
  void startEdit(Alarm alarm) => state = alarm;
  void update(Alarm alarm) => state = alarm;
  void clear() => state = null;
}

final draftProvider =
    StateNotifierProvider<DraftNotifier, Alarm?>((ref) => DraftNotifier());

/// The message shown by the ToastHost, or null when no toast is visible.
final toastProvider = StateProvider<String?>((ref) => null);
```

- [ ] **Step 7: Write the provider test**

Create `test/ui/state/alarm_providers_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:rise/data/alarm_sync_service.dart';
import 'package:rise/data/local/alarm_repository.dart';
import 'package:rise/data/local/database.dart';
import 'package:rise/domain/alarm.dart';
import 'package:rise/domain/scheduled_occurrence.dart';
import 'package:rise/ui/state/alarm_providers.dart';

class _FakePlatform implements AlarmPlatform {
  @override
  Future<void> reconcile(List<ScheduledOccurrence> o) async {}
  @override
  Future<void> ringNow(ScheduledOccurrence o) async {}
  @override
  Future<bool> supportsSystemAlarms() async => true;
  @override
  Future<void> reconcileNotifications(List requests) async {}
}

void main() {
  setUpAll(() => tzdata.initializeTimeZones());

  ProviderContainer makeContainer() {
    final db = RiseDatabase(NativeDatabase.memory());
    final service = AlarmSyncService(
      repository: AlarmRepository(db),
      platform: _FakePlatform(),
      location: tz.getLocation('America/New_York'),
    );
    addTearDown(db.close);
    return ProviderContainer(overrides: [
      alarmSyncServiceProvider.overrideWithValue(service),
    ]);
  }

  test('alarmsProvider streams alarms saved through the mutations', () async {
    final c = makeContainer();
    addTearDown(c.dispose);

    // Prime the stream.
    final sub = c.listen(alarmsProvider, (_, __) {});
    addTearDown(sub.close);

    await c.read(alarmMutationsProvider).save(
        const Alarm(id: 0, hour: 6, minute: 30, label: 'Run'));

    // The StreamProvider re-emits with the new alarm.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final alarms = c.read(alarmsProvider).value ?? const [];
    expect(alarms, hasLength(1));
    expect(alarms.single.label, 'Run');
  });

  test('draftProvider starts, edits, and clears', () {
    final c = makeContainer();
    addTearDown(c.dispose);
    final notifier = c.read(draftProvider.notifier);

    expect(c.read(draftProvider), isNull);
    notifier.startNew();
    expect(c.read(draftProvider)!.days, {1, 2, 3, 4, 5});
    notifier.update(c.read(draftProvider)!.copyWith(mission: 'math'));
    expect(c.read(draftProvider)!.mission, 'math');
    notifier.clear();
    expect(c.read(draftProvider), isNull);
  });
}
```

Run it:
```bash
flutter test test/ui/state/alarm_providers_test.dart
```
Expected: PASS — both tests green.

> `_FakePlatform.reconcileNotifications` takes `List` (untyped) to avoid importing the domain `NotificationRequest` in this test; the real interface uses `List<NotificationRequest>` but Dart accepts the wider positional type in an `implements` override only if it matches — if the analyzer rejects it, import `package:rise/domain/notification_request.dart` and type it `List<NotificationRequest>`.

- [ ] **Step 8: Run the whole suite and analyze**

```bash
flutter test
flutter analyze
```
Expected: all green (Plan 1/2 suites still pass — the migration keeps them working; the new fields default); `No issues found!`.

- [ ] **Step 9: Commit**

```bash
git add lib/domain/alarm.dart lib/data/local/database.dart lib/data/local/database.g.dart lib/data/local/alarm_repository.dart lib/ui/state/alarm_providers.dart pubspec.yaml pubspec.lock test/domain/alarm_test.dart test/data/migration_test.dart test/ui/state/alarm_providers_test.dart
git commit -m "feat: add mission fields (schema v2 migration) and the Riverpod state layer"
```

---

### Task 7: Home screen

**Files:**
- Create: `lib/ui/screens/home_screen.dart`
- Modify: `lib/ui/state/alarm_providers.dart` (add `nextOccurrenceProvider`)
- Test: `test/ui/screens/home_screen_test.dart`

**Interfaces:**
- Consumes: `alarmsProvider`, `alarmMutationsProvider`, `alarmSyncServiceProvider` (Task 6), the components (`RiseCard`, `GhostButton`, `SectionLabel`, `DayChips`, `RiseSwitch`), `repeatLabel`, tokens/typography; `Alarm`, `ScheduledOccurrence`.
- Produces:
  - `nextOccurrenceProvider` (`FutureProvider<ScheduledOccurrence?>`) — the soonest upcoming occurrence, or null.
  - `class HomeScreen extends ConsumerStatefulWidget` — `HomeScreen({required VoidCallback onNew, required void Function(Alarm) onEdit, required VoidCallback onPreview})`. Renders the greeting header, next-alarm hero (live 1s countdown), and the alarm list.

- [ ] **Step 1: Add nextOccurrenceProvider**

Append to `lib/ui/state/alarm_providers.dart`:

```dart
import '../../domain/scheduled_occurrence.dart';

/// The soonest upcoming alarm occurrence, or null if no alarm is enabled.
/// Recomputes whenever the alarm list changes.
final nextOccurrenceProvider = FutureProvider<ScheduledOccurrence?>((ref) async {
  ref.watch(alarmsProvider); // rebuild when alarms change
  final plan = await ref.watch(alarmSyncServiceProvider).currentPlan();
  return plan.isEmpty ? null : plan.first;
});
```

(Put the `import` at the top with the other imports.)

- [ ] **Step 2: Write the failing test**

Create `test/ui/screens/home_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/alarm.dart';
import 'package:rise/ui/screens/home_screen.dart';
import 'package:rise/ui/state/alarm_providers.dart';

class _RecordingMutations implements AlarmMutations {
  final List<(int, bool)> enabledCalls = [];
  @override
  Future<void> setEnabled(int id, bool enabled) async => enabledCalls.add((id, enabled));
  @override
  Future<void> save(Alarm alarm) async {}
  @override
  Future<void> delete(int id) async {}
}

Widget _host({
  required List<Alarm> alarms,
  required _RecordingMutations mutations,
  VoidCallback? onNew,
  void Function(Alarm)? onEdit,
}) {
  return ProviderScope(
    overrides: [
      alarmsProvider.overrideWith((ref) => Stream.value(alarms)),
      nextOccurrenceProvider.overrideWith((ref) async => null),
      alarmMutationsProvider.overrideWithValue(mutations),
    ],
    child: MaterialApp(
      home: HomeScreen(
        onNew: onNew ?? () {},
        onEdit: onEdit ?? (_) {},
        onPreview: () {},
      ),
    ),
  );
}

void main() {
  testWidgets('lists an alarm with its time and repeat label', (t) async {
    await t.pumpWidget(_host(
      alarms: const [Alarm(id: 1, hour: 6, minute: 30, label: 'Run', days: {1, 2, 3, 4, 5})],
      mutations: _RecordingMutations(),
    ));
    await t.pump();
    expect(find.text('6:30'), findsOneWidget);
    expect(find.textContaining('Run'), findsOneWidget);
    expect(find.textContaining('Weekdays'), findsOneWidget);
  });

  testWidgets('toggling a row calls setEnabled', (t) async {
    final m = _RecordingMutations();
    await t.pumpWidget(_host(
      alarms: const [Alarm(id: 7, hour: 6, minute: 30, enabled: true)],
      mutations: m,
    ));
    await t.pump();
    await t.tap(find.byType(Switch).first.hitTestable(), warnIfMissed: false);
    // The RiseSwitch is a GestureDetector, not a Material Switch — tap it by type.
    await t.pump();
    expect(m.enabledCalls, isNotEmpty);
    expect(m.enabledCalls.first, (7, false));
  });

  testWidgets('tapping a row calls onEdit', (t) async {
    Alarm? edited;
    await t.pumpWidget(_host(
      alarms: const [Alarm(id: 3, hour: 7, minute: 0)],
      mutations: _RecordingMutations(),
      onEdit: (a) => edited = a,
    ));
    await t.pump();
    await t.tap(find.text('7:00'));
    await t.pump();
    expect(edited?.id, 3);
  });

  testWidgets('empty state invites the user to add an alarm', (t) async {
    await t.pumpWidget(_host(alarms: const [], mutations: _RecordingMutations()));
    await t.pump();
    expect(find.textContaining('No alarms'), findsOneWidget);
  });
}
```

> The toggle test taps the `RiseSwitch` (a `GestureDetector`, not a Material `Switch`). Replace the `find.byType(Switch)` line with `await t.tap(find.byType(RiseSwitch).first);` (import `RiseSwitch`) — the placeholder above is a reminder; the implementer wires the real finder. Keep the assertion that `setEnabled(7, false)` was called.

- [ ] **Step 3: Run the test to verify it fails**

```bash
flutter test test/ui/screens/home_screen_test.dart
```
Expected: FAIL — `home_screen.dart` not found.

- [ ] **Step 4: Write the Home screen**

Create `lib/ui/screens/home_screen.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/alarm.dart';
import '../../domain/scheduled_occurrence.dart';
import '../components/day_chips.dart';
import '../components/rise_buttons.dart';
import '../components/rise_card.dart';
import '../components/rise_switch.dart';
import '../components/section_label.dart';
import '../state/alarm_providers.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

String _greeting() {
  final h = DateTime.now().hour;
  if (h < 12) return 'Good morning';
  if (h < 18) return 'Good afternoon';
  return 'Good evening';
}

String _countdown(Duration d) {
  if (d.isNegative || d.inSeconds == 0) return 'now';
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  if (h > 0) return 'in ${h}h ${m}m';
  return 'in ${m}m ${s.toString().padLeft(2, '0')}s';
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({
    super.key,
    required this.onNew,
    required this.onEdit,
    required this.onPreview,
  });

  final VoidCallback onNew;
  final void Function(Alarm) onEdit;
  final VoidCallback onPreview;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Drives the hero's live countdown.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alarmsAsync = ref.watch(alarmsProvider);
    final alarms = alarmsAsync.value ?? const <Alarm>[];
    final next = ref.watch(nextOccurrenceProvider).value;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            RiseSpacing.screen, 8, RiseSpacing.screen, 108),
        children: [
          _header(),
          const SizedBox(height: 18),
          _hero(alarms, next),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SectionLabel('Your alarms'),
              GhostButton(label: '+ New', onPressed: widget.onNew),
            ],
          ),
          const SizedBox(height: 12),
          if (alarms.isEmpty)
            _empty()
          else
            for (final a in alarms) ...[
              _AlarmRow(
                alarm: a,
                onEdit: () => widget.onEdit(a),
                onToggle: (v) =>
                    ref.read(alarmMutationsProvider).setEnabled(a.id, v),
              ),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }

  Widget _header() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_greeting(), style: RiseText.display),
        Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(color: RiseColors.primary, shape: BoxShape.circle),
          child: const Icon(Icons.person, color: RiseColors.primaryText, size: 20),
        ),
      ],
    );
  }

  Widget _hero(List<Alarm> alarms, ScheduledOccurrence? next) {
    if (next == null) {
      return RiseCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('Next alarm'),
              const SizedBox(height: 10),
              Text('No alarm set',
                  style: RiseText.mono(size: 24, color: RiseColors.textFaint)),
            ],
          ),
        ),
      );
    }

    Alarm? alarm;
    for (final a in alarms) {
      if (a.id == next.alarmId) {
        alarm = a;
        break;
      }
    }
    final hour12 = alarm?.hour12 ?? 0;
    final minute = alarm?.minute ?? 0;
    final ampm = (alarm?.isAm ?? true) ? 'AM' : 'PM';
    final remaining = next.fireAt.toLocal().difference(DateTime.now());

    return RiseCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionLabel('Next alarm'),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text('$hour12:${minute.toString().padLeft(2, '0')}',
                          style: RiseText.mono(size: 46, weight: FontWeight.w500)),
                      const SizedBox(width: 8),
                      Text(ampm, style: RiseText.mono(size: 16, color: RiseColors.textDim)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text('${next.label} · rings ',
                          style: RiseText.caption),
                      Text(_countdown(remaining),
                          style: RiseText.caption.copyWith(
                              color: RiseColors.accent, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: RiseColors.accentSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.notifications_active_outlined,
                    color: RiseColors.accent, size: 22),
              ),
            ],
          ),
          const SizedBox(height: 16),
          PrimaryButton(
              label: 'Preview alarm', icon: Icons.play_arrow, onPressed: widget.onPreview),
        ],
      ),
    );
  }

  Widget _empty() {
    return RiseCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: Text('No alarms yet. Tap New to set one.',
              style: RiseText.caption),
        ),
      ),
    );
  }
}

class _AlarmRow extends StatelessWidget {
  const _AlarmRow({required this.alarm, required this.onEdit, required this.onToggle});

  final Alarm alarm;
  final VoidCallback onEdit;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: alarm.enabled ? 1 : 0.62,
      child: RiseCard(
        radius: RiseRadii.base,
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onEdit,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text('${alarm.hour12}:${alarm.minute.toString().padLeft(2, '0')}',
                            style: RiseText.mono(
                                size: 27,
                                color: alarm.enabled ? RiseColors.text : RiseColors.textFaint)),
                        const SizedBox(width: 6),
                        Text(alarm.isAm ? 'AM' : 'PM',
                            style: RiseText.mono(size: 13, color: RiseColors.textDim)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text('${alarm.label} · ${repeatLabel(alarm.days)}',
                        style: RiseText.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 9),
                    DayChips(days: alarm.days, compact: true),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            RiseSwitch(value: alarm.enabled, onChanged: onToggle),
          ],
        ),
      ),
    );
  }
}
```

> The header shows a time-based greeting and a neutral avatar — no fake user name, no streak pill; those belong to the profile/stats plans (5/7) and are added when real data exists. The Crew·live strip is omitted this plan.

- [ ] **Step 5: Fix the toggle test's finder**

In `test/ui/screens/home_screen_test.dart`, replace the placeholder toggle line with a real `RiseSwitch` tap (add `import 'package:rise/ui/components/rise_switch.dart';`):

```dart
    await t.tap(find.byType(RiseSwitch).first);
```

- [ ] **Step 6: Run the test to verify it passes**

```bash
flutter test test/ui/screens/home_screen_test.dart
```
Expected: PASS — 4 tests green.

- [ ] **Step 7: Run the whole suite and analyze**

```bash
flutter test
flutter analyze
```
Expected: all green; `No issues found!`.

- [ ] **Step 8: Commit**

```bash
git add lib/ui/screens/home_screen.dart lib/ui/state/alarm_providers.dart test/ui/screens/home_screen_test.dart
git commit -m "feat(ui): add the Home screen with next-alarm hero and alarm list"
```

---

### Task 8: Create/Edit alarm screen

**Files:**
- Create: `lib/domain/alarm_sounds.dart` (the selectable-sound catalog)
- Create: `lib/ui/screens/create_edit_screen.dart`
- Test: `test/domain/alarm_sounds_test.dart`
- Test: `test/ui/screens/create_edit_screen_test.dart`

**Interfaces:**
- Consumes: `draftProvider`/`DraftNotifier` (`startNew`/`startEdit`/`update`/`clear`), `alarmMutationsProvider` (`save(Alarm)`/`delete(int)`), `toastProvider`; `Alarm` (`copyWith`, `hour12`, `isAm`, `Alarm.to24Hour`); components `TimeDial` (`DialTime = ({int hour12, int minute, bool isAm})`), `DayChips`, `SoundChips`, `SegmentedControl<T>` (`segments: List<({T value, String label})>`), `RiseSwitch`, `RiseCard`, `SectionLabel`, `PrimaryButton`; tokens/typography.
- Produces:
  - `class AlarmSound { const AlarmSound(this.label, this.asset); final String label; final String asset; }`, `const List<AlarmSound> kAlarmSounds`, `String soundLabelFor(String asset)`, `String soundAssetFor(String label)`.
  - `class CreateEditScreen extends ConsumerStatefulWidget` — `CreateEditScreen({required VoidCallback onDone})`. Edits the current `draftProvider` alarm in place; Save persists + arms via `alarmMutationsProvider` then calls `onDone`; Delete (edit mode only) removes + `onDone`; Cancel clears + `onDone`.

- [ ] **Step 1: Write the failing sound-catalog test**

Create `test/domain/alarm_sounds_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/alarm_sounds.dart';

void main() {
  test('catalog is non-empty and Default maps to the entity default asset', () {
    expect(kAlarmSounds, isNotEmpty);
    expect(kAlarmSounds.first.label, 'Default');
    expect(kAlarmSounds.first.asset, 'sounds/default_alarm.mp3');
  });

  test('label<->asset round-trips for every catalog entry', () {
    for (final s in kAlarmSounds) {
      expect(soundLabelFor(s.asset), s.label);
      expect(soundAssetFor(s.label), s.asset);
    }
  });

  test('unknown asset or label falls back to the first entry', () {
    expect(soundLabelFor('sounds/does_not_exist.mp3'), kAlarmSounds.first.label);
    expect(soundAssetFor('Nonexistent'), kAlarmSounds.first.asset);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
flutter test test/domain/alarm_sounds_test.dart
```
Expected: FAIL — `alarm_sounds.dart` not found.

- [ ] **Step 3: Write the sound catalog**

Create `lib/domain/alarm_sounds.dart`:

```dart
/// A selectable alarm tone. [asset] is the bundled audio path handed to the
/// native player. Until real audio files are bundled, the native layer falls
/// back to the platform default alarm tone for any missing asset — so every
/// option currently rings the system default. The user's choice is still
/// persisted and is ready to sound the moment the files are added.
class AlarmSound {
  const AlarmSound(this.label, this.asset);
  final String label;
  final String asset;
}

/// The first entry MUST be 'Default' → the entity's default `soundAsset`, so an
/// alarm created with no explicit sound reverse-maps to a selected chip.
const List<AlarmSound> kAlarmSounds = [
  AlarmSound('Default', 'sounds/default_alarm.mp3'),
  AlarmSound('Radar', 'sounds/radar.mp3'),
  AlarmSound('Chimes', 'sounds/chimes.mp3'),
  AlarmSound('Beacon', 'sounds/beacon.mp3'),
  AlarmSound('Signal', 'sounds/signal.mp3'),
];

/// The display label for a stored asset path; falls back to the first entry.
String soundLabelFor(String asset) => kAlarmSounds
    .firstWhere((s) => s.asset == asset, orElse: () => kAlarmSounds.first)
    .label;

/// The asset path for a display label; falls back to the first entry.
String soundAssetFor(String label) => kAlarmSounds
    .firstWhere((s) => s.label == label, orElse: () => kAlarmSounds.first)
    .asset;
```

- [ ] **Step 4: Run it to verify it passes**

```bash
flutter test test/domain/alarm_sounds_test.dart
```
Expected: PASS — 3 tests green.

- [ ] **Step 5: Write the failing Create/Edit widget test**

Create `test/ui/screens/create_edit_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/alarm.dart';
import 'package:rise/ui/components/segmented.dart';
import 'package:rise/ui/screens/create_edit_screen.dart';
import 'package:rise/ui/state/alarm_providers.dart';

class _RecordingMutations implements AlarmMutations {
  final List<Alarm> saved = [];
  final List<int> deleted = [];
  @override
  Future<void> save(Alarm alarm) async => saved.add(alarm);
  @override
  Future<void> delete(int id) async => deleted.add(id);
  @override
  Future<void> setEnabled(int id, bool enabled) async {}
}

ProviderContainer _container(_RecordingMutations m) {
  final c = ProviderContainer(
    overrides: [alarmMutationsProvider.overrideWithValue(m)],
  );
  addTearDown(c.dispose);
  return c;
}

Widget _host(ProviderContainer c, {VoidCallback? onDone}) {
  return UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      home: Scaffold(body: CreateEditScreen(onDone: onDone ?? () {})),
    ),
  );
}

void main() {
  testWidgets('edit mode shows the alarm time, label, and "Edit alarm" title', (t) async {
    final c = _container(_RecordingMutations());
    c.read(draftProvider.notifier).startEdit(
        const Alarm(id: 5, hour: 6, minute: 30, label: 'Run', days: {1, 2, 3}));
    await t.pumpWidget(_host(c));
    await t.pump();
    expect(find.text('Edit alarm'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);        // hour dial
    expect(find.text('30'), findsOneWidget);       // minute dial
    expect(find.widgetWithText(TextField, 'Run'), findsOneWidget);
    expect(find.text('Delete alarm'), findsOneWidget);
  });

  testWidgets('new mode shows "New alarm" and no delete button', (t) async {
    final c = _container(_RecordingMutations());
    c.read(draftProvider.notifier).startNew();
    await t.pumpWidget(_host(c));
    await t.pump();
    expect(find.text('New alarm'), findsOneWidget);
    expect(find.text('Delete alarm'), findsNothing);
  });

  testWidgets('tapping a day chip toggles it in the draft', (t) async {
    final c = _container(_RecordingMutations());
    c.read(draftProvider.notifier)
        .startEdit(const Alarm(id: 5, hour: 6, minute: 30, days: {}));
    await t.pumpWidget(_host(c));
    await t.pump();
    // Monday is index 1; tap the 'M' chip.
    await t.tap(find.text('M'));
    await t.pump();
    expect(c.read(draftProvider)!.days.contains(1), isTrue);
  });

  testWidgets('difficulty control appears only when a mission is chosen', (t) async {
    final c = _container(_RecordingMutations());
    c.read(draftProvider.notifier).startEdit(
        const Alarm(id: 5, hour: 6, minute: 30, mission: 'none'));
    await t.pumpWidget(_host(c));
    await t.pump();
    expect(find.byType(SegmentedControl<String>), findsNothing);
    await t.tap(find.text('Math'));
    await t.pump();
    expect(find.byType(SegmentedControl<String>), findsOneWidget);
    expect(c.read(draftProvider)!.mission, 'math');
  });

  testWidgets('Save persists the draft, arms it, and calls onDone', (t) async {
    final m = _RecordingMutations();
    final c = _container(m);
    var doneCalled = false;
    c.read(draftProvider.notifier)
        .startEdit(const Alarm(id: 5, hour: 6, minute: 30, label: 'Run'));
    await t.pumpWidget(_host(c, onDone: () => doneCalled = true));
    await t.pump();
    await t.tap(find.text('Save alarm'));
    await t.pumpAndSettle();
    expect(m.saved.single.id, 5);
    expect(m.saved.single.label, 'Run');
    expect(doneCalled, isTrue);
  });

  testWidgets('Delete removes the alarm and calls onDone', (t) async {
    final m = _RecordingMutations();
    final c = _container(m);
    var doneCalled = false;
    c.read(draftProvider.notifier)
        .startEdit(const Alarm(id: 5, hour: 6, minute: 30));
    await t.pumpWidget(_host(c, onDone: () => doneCalled = true));
    await t.pump();
    await t.tap(find.text('Delete alarm'));
    await t.pumpAndSettle();
    expect(m.deleted.single, 5);
    expect(doneCalled, isTrue);
  });
}
```

- [ ] **Step 6: Run it to verify it fails**

```bash
flutter test test/ui/screens/create_edit_screen_test.dart
```
Expected: FAIL — `create_edit_screen.dart` not found.

- [ ] **Step 7: Write the Create/Edit screen**

Create `lib/ui/screens/create_edit_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/alarm.dart';
import '../../domain/alarm_sounds.dart';
import '../components/day_chips.dart';
import '../components/rise_buttons.dart';
import '../components/rise_card.dart';
import '../components/rise_switch.dart';
import '../components/section_label.dart';
import '../components/segmented.dart';
import '../components/sound_chips.dart';
import '../components/time_dial.dart';
import '../state/alarm_providers.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Mission keys ↔ display labels. The `SoundChips` pill row is a generic
/// single-select chip strip, reused here for the mission picker.
const Map<String, String> _missionLabels = {
  'none': 'None',
  'math': 'Math',
  'hold': 'Hold',
  'tap': 'Tap',
  'memory': 'Memory',
};

class CreateEditScreen extends ConsumerStatefulWidget {
  const CreateEditScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  ConsumerState<CreateEditScreen> createState() => _CreateEditScreenState();
}

class _CreateEditScreenState extends ConsumerState<CreateEditScreen> {
  late final TextEditingController _label;

  @override
  void initState() {
    super.initState();
    // Seed once from the draft set before navigation; the controller then owns
    // the text so watching the draft in build() won't fight the user's typing.
    _label = TextEditingController(text: ref.read(draftProvider)?.label ?? '');
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  void _update(Alarm next) => ref.read(draftProvider.notifier).update(next);

  Future<void> _save(Alarm draft) async {
    await ref.read(alarmMutationsProvider).save(draft);
    if (!mounted) return;
    ref.read(toastProvider.notifier).state = 'Alarm saved';
    ref.read(draftProvider.notifier).clear();
    widget.onDone();
  }

  Future<void> _delete(int id) async {
    await ref.read(alarmMutationsProvider).delete(id);
    if (!mounted) return;
    ref.read(toastProvider.notifier).state = 'Alarm deleted';
    ref.read(draftProvider.notifier).clear();
    widget.onDone();
  }

  void _cancel() {
    ref.read(draftProvider.notifier).clear();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(draftProvider);
    if (draft == null) return const SizedBox.shrink();
    final isEdit = draft.id != 0;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            RiseSpacing.screen, 8, RiseSpacing.screen, 40),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GhostButton(label: 'Cancel', onPressed: _cancel),
              Text(isEdit ? 'Edit alarm' : 'New alarm', style: RiseText.title),
              const SizedBox(width: 64), // balances the Cancel button
            ],
          ),
          const SizedBox(height: 12),
          RiseCard(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: TimeDial(
              value: (hour12: draft.hour12, minute: draft.minute, isAm: draft.isAm),
              onChanged: (t) => _update(draft.copyWith(
                hour: Alarm.to24Hour(t.hour12, t.isAm),
                minute: t.minute,
                clearLastDismissedAt: true, // editing time clears a stale dismissal
              )),
            ),
          ),
          _section('Repeat', DayChips(
            days: draft.days,
            onToggle: (i) {
              final next = {...draft.days};
              next.contains(i) ? next.remove(i) : next.add(i);
              _update(draft.copyWith(days: next));
            },
          ),
          trailing: Text(repeatLabel(draft.days), style: RiseText.caption)),
          _section('Label', TextField(
            controller: _label,
            onChanged: (v) => _update(draft.copyWith(label: v)),
            style: RiseText.body,
            cursorColor: RiseColors.primary,
            decoration: InputDecoration(
              hintText: 'Alarm',
              hintStyle: RiseText.body.copyWith(color: RiseColors.textFaint),
              filled: true,
              fillColor: RiseColors.surface2,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: _fieldBorder(RiseColors.border),
              enabledBorder: _fieldBorder(RiseColors.border),
              focusedBorder: _fieldBorder(RiseColors.primary),
            ),
          )),
          _section('Sound', SoundChips(
            sounds: kAlarmSounds.map((s) => s.label).toList(),
            selected: soundLabelFor(draft.soundAsset),
            onChanged: (label) =>
                _update(draft.copyWith(soundAsset: soundAssetFor(label))),
          )),
          _section('Wake mission', SoundChips(
            sounds: _missionLabels.values.toList(),
            selected: _missionLabels[draft.mission]!,
            onChanged: (label) {
              final key = _missionLabels.entries
                  .firstWhere((e) => e.value == label)
                  .key;
              _update(draft.copyWith(mission: key));
            },
          )),
          if (draft.mission != 'none')
            _section('Difficulty', SegmentedControl<String>(
              segments: const [
                (value: 'easy', label: 'Easy'),
                (value: 'medium', label: 'Medium'),
                (value: 'hard', label: 'Hard'),
              ],
              selected: draft.missionDiff,
              onChanged: (d) => _update(draft.copyWith(missionDiff: d)),
            )),
          const SizedBox(height: 20),
          RiseCard(
            radius: RiseRadii.base,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Vibrate', style: RiseText.body),
                RiseSwitch(
                  value: draft.vibrate,
                  onChanged: (v) => _update(draft.copyWith(vibrate: v)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          PrimaryButton(label: 'Save alarm', onPressed: () => _save(draft)),
          if (isEdit) ...[
            const SizedBox(height: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _delete(draft.id),
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 13),
                child: Text('Delete alarm',
                    style: RiseText.body.copyWith(
                        color: RiseColors.danger, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static OutlineInputBorder _fieldBorder(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(RiseRadii.base),
        borderSide: BorderSide(color: color),
      );

  Widget _section(String label, Widget child, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [SectionLabel(label), if (trailing != null) trailing],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
```

> The delete action is a danger-tinted text button (the component set has no danger button, and adding one is out of scope). Editing the time clears `lastDismissedAt` (per the `Alarm.copyWith` contract) so a stale dismissal can't suppress the edited occurrence. The screen returns bare content (no `Scaffold`); its host — the app shell in Task 13, and a `Scaffold` in the tests — supplies the `Material` ancestor the label `TextField` needs.

- [ ] **Step 8: Run both new test files to verify they pass**

```bash
flutter test test/domain/alarm_sounds_test.dart test/ui/screens/create_edit_screen_test.dart
```
Expected: PASS — 3 + 6 tests green.

- [ ] **Step 9: Run the whole suite and analyze**

```bash
flutter test
flutter analyze
```
Expected: all green; `No issues found!`.

- [ ] **Step 10: Commit**

```bash
git add lib/domain/alarm_sounds.dart lib/ui/screens/create_edit_screen.dart test/domain/alarm_sounds_test.dart test/ui/screens/create_edit_screen_test.dart
git commit -m "feat(ui): add the Create/Edit alarm screen with sound catalog"
```

---

### Task 9: Ring screen (replaces DevRingPage's logic)

**Files:**
- Create: `lib/ui/screens/ring_screen.dart`
- Test: `test/ui/screens/ring_screen_test.dart`

**Interfaces:**
- Consumes: `alarmsProvider` (to read the ringing alarm's label/mission); `AlarmHostApi().stopRinging` + `AlarmSyncService.instance` (for the production dismissal only); `SlideToWake`, tokens/typography; `Alarm`.
- Produces:
  - `typedef MissionBuilder = Widget Function(BuildContext context, Alarm alarm, VoidCallback onSolved);`
  - `Future<void> dismissRingingAlarm(int alarmId)` — the production dismissal (stop → record → reconcile, in that exact order).
  - `class RingScreen extends ConsumerStatefulWidget` — `RingScreen({required int alarmId, VoidCallback? onDismissed, Future<void> Function(int) dismissAlarm = dismissRingingAlarm, MissionBuilder? missionBuilder})`. Task 14 swaps `main.dart`'s `DevRingPage` for this and passes `onDismissed`; Task 10 supplies `missionBuilder`.

> This task does NOT touch `main.dart` — `DevRingPage` stays wired until Task 14. `RingScreen` is built and tested standalone. The dismissal ordering (silence first, unconditional; record + reconcile second, best-effort) is copied faithfully from `DevRingPage` — it is load-bearing and was validated on a physical device in Plan 1.

- [ ] **Step 1: Write the failing test**

Create `test/ui/screens/ring_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/alarm.dart';
import 'package:rise/ui/components/slide_to_wake.dart';
import 'package:rise/ui/screens/ring_screen.dart';
import 'package:rise/ui/state/alarm_providers.dart';

Widget _host({
  required List<Alarm> alarms,
  required int alarmId,
  Future<void> Function(int)? dismissAlarm,
  VoidCallback? onDismissed,
  MissionBuilder? missionBuilder,
}) {
  return ProviderScope(
    overrides: [alarmsProvider.overrideWith((ref) => Stream.value(alarms))],
    child: MaterialApp(
      home: RingScreen(
        alarmId: alarmId,
        onDismissed: onDismissed,
        dismissAlarm: dismissAlarm ?? (_) async {},
        missionBuilder: missionBuilder,
      ),
    ),
  );
}

void main() {
  testWidgets('no-mission alarm shows slide-to-wake; sliding dismisses', (t) async {
    int? dismissed;
    var doneCalled = false;
    await t.pumpWidget(_host(
      alarms: const [Alarm(id: 5, hour: 6, minute: 30, label: 'Run')],
      alarmId: 5,
      dismissAlarm: (id) async => dismissed = id,
      onDismissed: () => doneCalled = true,
    ));
    await t.pump(); // let alarmsProvider emit
    expect(find.byType(SlideToWake), findsOneWidget);
    await t.drag(find.byType(SlideToWake), const Offset(1000, 0));
    await t.pump();
    await t.pump(const Duration(milliseconds: 20));
    expect(dismissed, 5);
    expect(doneCalled, isTrue);
  });

  testWidgets('shows the alarm label', (t) async {
    await t.pumpWidget(_host(
      alarms: const [Alarm(id: 5, hour: 6, minute: 30, label: 'Gym time')],
      alarmId: 5,
    ));
    await t.pump();
    expect(find.text('Gym time'), findsOneWidget);
  });

  testWidgets('a missioned alarm with a missionBuilder shows the mission, not the slider', (t) async {
    int? dismissed;
    await t.pumpWidget(_host(
      alarms: const [Alarm(id: 7, hour: 6, minute: 30, mission: 'math')],
      alarmId: 7,
      dismissAlarm: (id) async => dismissed = id,
      missionBuilder: (context, alarm, onSolved) =>
          TextButton(onPressed: onSolved, child: const Text('SOLVE')),
    ));
    await t.pump();
    expect(find.byType(SlideToWake), findsNothing);
    expect(find.text('SOLVE'), findsOneWidget);
    await t.tap(find.text('SOLVE'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 20));
    expect(dismissed, 7);
  });

  testWidgets('unknown alarm still shows a slider so the user can dismiss', (t) async {
    await t.pumpWidget(_host(alarms: const [], alarmId: 999));
    await t.pump();
    expect(find.byType(SlideToWake), findsOneWidget);
  });

  testWidgets('a failed dismissal keeps the screen so the user can retry', (t) async {
    var doneCalled = false;
    await t.pumpWidget(_host(
      alarms: const [Alarm(id: 5, hour: 6, minute: 30)],
      alarmId: 5,
      dismissAlarm: (_) async => throw StateError('stop failed'),
      onDismissed: () => doneCalled = true,
    ));
    await t.pump();
    await t.drag(find.byType(SlideToWake), const Offset(1000, 0));
    await t.pump();
    await t.pump(const Duration(milliseconds: 20));
    expect(doneCalled, isFalse);
    expect(find.byType(RingScreen), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
flutter test test/ui/screens/ring_screen_test.dart
```
Expected: FAIL — `ring_screen.dart` not found.

- [ ] **Step 3: Write the ring screen**

Create `lib/ui/screens/ring_screen.dart`:

```dart
import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/alarm_sync_service.dart';
import '../../data/native/alarm_api.g.dart';
import '../../domain/alarm.dart';
import '../components/slide_to_wake.dart';
import '../state/alarm_providers.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Builds the dismissal gate for a missioned alarm. Task 10 supplies the real
/// mission widgets; [onSolved] must be called exactly once when the user
/// completes the mission — that dismisses the alarm.
typedef MissionBuilder = Widget Function(
    BuildContext context, Alarm alarm, VoidCallback onSolved);

/// Fully dismisses a ringing alarm. The order is deliberate and load-bearing
/// (validated on a physical device in Plan 1):
///
/// 1. [AlarmHostApi.stopRinging] runs FIRST and unconditionally — a user who
///    dismisses must get silence immediately, never gated on a database write
///    that can block for seconds under SQLite contention. It talks straight to
///    the native side and does not depend on the Dart service being configured,
///    so a ringing alarm is always stoppable.
/// 2. Recording the dismissal + reconciling is best-effort and MUST run after
///    stopRinging: it disables a fired one-shot so reconcile does not re-arm it
///    for tomorrow. A failure here is logged, not fatal — the alarm is already
///    silent.
///
/// If stopRinging itself throws (a real platform failure — the alarm may still
/// be sounding), the throw propagates so the caller keeps the ring screen up
/// for a retry instead of falsely reporting success.
Future<void> dismissRingingAlarm(int alarmId) async {
  await AlarmHostApi().stopRinging(alarmId);
  try {
    await AlarmSyncService.instance.repository
        .recordDismissed(alarmId, DateTime.now().toUtc());
    await AlarmSyncService.instance.reconcileNow();
  } catch (e) {
    debugPrint('Rise: could not record dismissal for alarm $alarmId: $e');
  }
}

class RingScreen extends ConsumerStatefulWidget {
  const RingScreen({
    super.key,
    required this.alarmId,
    this.onDismissed,
    this.dismissAlarm = dismissRingingAlarm,
    this.missionBuilder,
  });

  final int alarmId;

  /// Called after the alarm is fully dismissed — the host pops the screen.
  final VoidCallback? onDismissed;

  /// The dismissal work (stop → record → reconcile). Injectable for tests;
  /// defaults to [dismissRingingAlarm].
  final Future<void> Function(int alarmId) dismissAlarm;

  final MissionBuilder? missionBuilder;

  @override
  ConsumerState<RingScreen> createState() => _RingScreenState();
}

class _RingScreenState extends ConsumerState<RingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  Timer? _clock;
  bool _dismissing = false;
  int _attempt = 0; // bumped on a failed dismissal to reset the slider

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.92,
      upperBound: 1.08,
    )..repeat(reverse: true);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {}); // advances the live clock
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    if (_dismissing) return; // guard double-taps / repeated slide fires
    setState(() => _dismissing = true);
    try {
      await widget.dismissAlarm(widget.alarmId);
    } catch (e) {
      debugPrint('Rise: dismiss failed for ${widget.alarmId}: $e');
      if (mounted) {
        setState(() {
          _dismissing = false;
          _attempt++; // fresh key resets the slide-to-wake so it can fire again
        });
      }
      return;
    }
    if (!mounted) return;
    widget.onDismissed?.call();
  }

  @override
  Widget build(BuildContext context) {
    final alarm = ref
        .watch(alarmsProvider)
        .value
        ?.firstWhereOrNull((a) => a.id == widget.alarmId);
    final label = alarm?.label ?? 'Alarm';
    final now = DateTime.now();
    final hour12 = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final ampm = now.hour < 12 ? 'AM' : 'PM';
    final reduce = MediaQuery.of(context).disableAnimations;

    Widget bell = Container(
      width: 92,
      height: 92,
      decoration: BoxDecoration(
        color: RiseColors.accentSoft,
        borderRadius: BorderRadius.circular(28),
      ),
      child: const Icon(Icons.notifications_active,
          color: RiseColors.accent, size: 44),
    );
    if (!reduce) bell = ScaleTransition(scale: _pulse, child: bell);

    final gate = (alarm != null &&
            alarm.mission != 'none' &&
            widget.missionBuilder != null)
        ? widget.missionBuilder!(context, alarm, _dismiss)
        : SlideToWake(key: ValueKey(_attempt), onWake: _dismiss);

    return Scaffold(
      backgroundColor: RiseColors.appBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(RiseSpacing.screen),
          child: Column(
            children: [
              const Spacer(),
              bell,
              const SizedBox(height: 30),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('$hour12:${now.minute.toString().padLeft(2, '0')}',
                      style: RiseText.mono(size: 72, weight: FontWeight.w500)),
                  const SizedBox(width: 10),
                  Text(ampm,
                      style: RiseText.mono(size: 20, color: RiseColors.textDim)),
                ],
              ),
              const SizedBox(height: 10),
              Text(label, style: RiseText.title.copyWith(color: RiseColors.textDim)),
              const Spacer(),
              gate,
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run it to verify it passes**

```bash
flutter test test/ui/screens/ring_screen_test.dart
```
Expected: PASS — 5 tests green. (Use `flutter test` — the repeating pulse animation means `pumpAndSettle` would hang; the tests deliberately use `pump`.)

- [ ] **Step 5: Run the whole suite and analyze**

```bash
flutter test
flutter analyze
```
Expected: all green; `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git add lib/ui/screens/ring_screen.dart test/ui/screens/ring_screen_test.dart
git commit -m "feat(ui): add the ring screen with slide-to-wake and mission seam"
```

---

### Task 10: Wake missions (Math / Hold / Tap / Memory) + host

**Files:**
- Create: `lib/ui/missions/mission_frame.dart`
- Create: `lib/ui/missions/math_mission.dart`
- Create: `lib/ui/missions/hold_mission.dart`
- Create: `lib/ui/missions/tap_mission.dart`
- Create: `lib/ui/missions/memory_mission.dart`
- Create: `lib/ui/missions/mission_host.dart`
- Test: `test/ui/missions/missions_test.dart`

**Interfaces:**
- Consumes: components/tokens (`PrimaryButton`, `RiseColors`, `RiseRadii`, `RiseShadows`, `RiseText`); `Alarm`; `RingScreen`'s `MissionBuilder` shape and `alarmsProvider`/`SlideToWake` (for the integration test).
- Produces:
  - `MissionFrame({required String instruction, required Widget child})`.
  - `MathMission`/`HoldMission`/`TapMission`/`MemoryMission` — each `StatefulWidget({required String diff, required VoidCallback onSolved, <injectable override>})`, calling `onSolved` exactly once on completion.
  - Difficulty helpers `generateMathProblem`, `holdDurationFor`, `tapTargetFor`, `memoryLengthFor`, `generateSequence`.
  - `Widget buildMission(BuildContext, Alarm, VoidCallback onSolved)` — structurally a `MissionBuilder`; dispatches on `alarm.mission`. Task 14 passes it to `RingScreen(missionBuilder: buildMission)`.

> Each mission takes an injectable override (a fixed math problem, a tiny hold duration, a small tap target, a known memory sequence) so tests are deterministic and fast. `'none'` never reaches `buildMission` (RingScreen shows slide-to-wake for it); the host maps it to an empty box defensively.

- [ ] **Step 1: Write the failing test**

Create `test/ui/missions/missions_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/alarm.dart';
import 'package:rise/ui/components/slide_to_wake.dart';
import 'package:rise/ui/missions/hold_mission.dart';
import 'package:rise/ui/missions/math_mission.dart';
import 'package:rise/ui/missions/memory_mission.dart';
import 'package:rise/ui/missions/mission_host.dart';
import 'package:rise/ui/missions/tap_mission.dart';
import 'package:rise/ui/screens/ring_screen.dart';
import 'package:rise/ui/state/alarm_providers.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  group('MathMission', () {
    testWidgets('correct answer solves', (t) async {
      var solved = false;
      await t.pumpWidget(_wrap(MathMission(
        diff: 'easy',
        onSolved: () => solved = true,
        problem: (prompt: '2 + 3', answer: 5),
      )));
      await t.enterText(find.byType(TextField), '5');
      await t.tap(find.text('Check'));
      await t.pump();
      expect(solved, isTrue);
    });

    testWidgets('wrong answer does not solve and shows a retry hint', (t) async {
      var solved = false;
      await t.pumpWidget(_wrap(MathMission(
        diff: 'easy',
        onSolved: () => solved = true,
        problem: (prompt: '2 + 3', answer: 5),
      )));
      await t.enterText(find.byType(TextField), '9');
      await t.tap(find.text('Check'));
      await t.pump();
      expect(solved, isFalse);
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  test('generateMathProblem answer is consistent with its operands', () {
    for (final d in ['easy', 'medium', 'hard']) {
      final p = generateMathProblem(d);
      expect(p.answer, greaterThan(0));
      expect(p.prompt, isNotEmpty);
    }
  });

  group('HoldMission', () {
    testWidgets('holding until the timer completes solves', (t) async {
      var solved = false;
      await t.pumpWidget(_wrap(HoldMission(
        diff: 'easy',
        onSolved: () => solved = true,
        holdDuration: const Duration(milliseconds: 100),
      )));
      final g = await t.startGesture(t.getCenter(find.text('HOLD')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 130));
      expect(solved, isTrue);
      await g.up();
    });

    testWidgets('releasing early does not solve', (t) async {
      var solved = false;
      await t.pumpWidget(_wrap(HoldMission(
        diff: 'easy',
        onSolved: () => solved = true,
        holdDuration: const Duration(milliseconds: 100),
      )));
      final g = await t.startGesture(t.getCenter(find.text('HOLD')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 40));
      await g.up();
      await t.pump(const Duration(milliseconds: 200));
      expect(solved, isFalse);
    });
  });

  testWidgets('TapMission: reaching the target solves', (t) async {
    var solved = false;
    await t.pumpWidget(_wrap(TapMission(
      diff: 'easy',
      onSolved: () => solved = true,
      targetTaps: 3,
    )));
    await t.tap(find.text('3'));
    await t.pump();
    await t.tap(find.text('2'));
    await t.pump();
    await t.tap(find.text('1'));
    await t.pump();
    expect(solved, isTrue);
  });

  group('MemoryMission', () {
    testWidgets('repeating the shown sequence solves', (t) async {
      var solved = false;
      await t.pumpWidget(_wrap(MemoryMission(
        diff: 'easy',
        onSolved: () => solved = true,
        sequence: const [0, 1, 2],
      )));
      await t.pump(); // start playback
      await t.pump(const Duration(seconds: 2)); // playback done, input opens
      await t.tap(find.byKey(const ValueKey('mem-pad-0')));
      await t.tap(find.byKey(const ValueKey('mem-pad-1')));
      await t.tap(find.byKey(const ValueKey('mem-pad-2')));
      await t.pump();
      expect(solved, isTrue);
    });

    testWidgets('a wrong tap does not solve', (t) async {
      var solved = false;
      await t.pumpWidget(_wrap(MemoryMission(
        diff: 'easy',
        onSolved: () => solved = true,
        sequence: const [0, 1, 2],
      )));
      await t.pump();
      await t.pump(const Duration(seconds: 2));
      await t.tap(find.byKey(const ValueKey('mem-pad-3'))); // wrong first pad
      await t.pump();
      expect(solved, isFalse);
    });
  });

  group('buildMission host', () {
    testWidgets('dispatches to the right mission widget', (t) async {
      final cases = <String, Type>{
        'math': MathMission,
        'hold': HoldMission,
        'tap': TapMission,
        'memory': MemoryMission,
      };
      for (final entry in cases.entries) {
        await t.pumpWidget(_wrap(Builder(
          builder: (context) => buildMission(
            context,
            Alarm(id: 1, hour: 6, minute: 0, mission: entry.key),
            () {},
          ),
        )));
        await t.pump();
        expect(find.byType(entry.value), findsOneWidget,
            reason: 'mission ${entry.key}');
      }
    });

    testWidgets('RingScreen with the host shows the mission for a missioned alarm',
        (t) async {
      await t.pumpWidget(ProviderScope(
        overrides: [
          alarmsProvider.overrideWith((ref) => Stream.value(
              const [Alarm(id: 7, hour: 6, minute: 30, mission: 'tap')])),
        ],
        child: MaterialApp(
          home: RingScreen(
            alarmId: 7,
            dismissAlarm: (_) async {},
            missionBuilder: buildMission,
          ),
        ),
      ));
      await t.pump();
      expect(find.byType(TapMission), findsOneWidget);
      expect(find.byType(SlideToWake), findsNothing);
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
flutter test test/ui/missions/missions_test.dart
```
Expected: FAIL — mission files not found.

- [ ] **Step 3: Create the shared frame**

Create `lib/ui/missions/mission_frame.dart`:

```dart
import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Common presentation for a wake mission: a bold instruction above the
/// interactive area.
class MissionFrame extends StatelessWidget {
  const MissionFrame({super.key, required this.instruction, required this.child});

  final String instruction;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(instruction,
            textAlign: TextAlign.center,
            style: RiseText.body
                .copyWith(color: RiseColors.textDim, fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        child,
      ],
    );
  }
}
```

- [ ] **Step 4: Create the Math mission**

Create `lib/ui/missions/math_mission.dart`:

```dart
import 'dart:math';

import 'package:flutter/material.dart';

import '../components/rise_buttons.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'mission_frame.dart';

typedef MathProblem = ({String prompt, int answer});

/// A random arithmetic problem scaled by difficulty. Pass [rng] for
/// determinism in tests.
MathProblem generateMathProblem(String diff, [Random? rng]) {
  final r = rng ?? Random();
  switch (diff) {
    case 'hard':
      final a = 3 + r.nextInt(11); // 3..13
      final b = 3 + r.nextInt(11);
      return (prompt: '$a × $b', answer: a * b);
    case 'medium':
      final a = 10 + r.nextInt(40); // 10..49
      final b = 10 + r.nextInt(40);
      return (prompt: '$a + $b', answer: a + b);
    default: // easy
      final a = 2 + r.nextInt(18); // 2..19
      final b = 2 + r.nextInt(18);
      return (prompt: '$a + $b', answer: a + b);
  }
}

class MathMission extends StatefulWidget {
  const MathMission({
    super.key,
    required this.diff,
    required this.onSolved,
    this.problem, // injectable for tests
  });

  final String diff;
  final VoidCallback onSolved;
  final MathProblem? problem;

  @override
  State<MathMission> createState() => _MathMissionState();
}

class _MathMissionState extends State<MathMission> {
  late MathProblem _p;
  final _controller = TextEditingController();
  bool _wrong = false;

  @override
  void initState() {
    super.initState();
    _p = widget.problem ?? generateMathProblem(widget.diff);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (int.tryParse(_controller.text.trim()) == _p.answer) {
      widget.onSolved();
      return;
    }
    setState(() {
      _wrong = true;
      _controller.clear();
      // A fresh problem (when not injected) so guessing can't brute-force it.
      _p = widget.problem ?? generateMathProblem(widget.diff);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MissionFrame(
      instruction: 'Solve to dismiss',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${_p.prompt} = ?',
              style: RiseText.mono(size: 40, weight: FontWeight.w500)),
          const SizedBox(height: 16),
          SizedBox(
            width: 160,
            child: TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: RiseText.mono(size: 24),
              cursorColor: RiseColors.primary,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: '?',
                filled: true,
                fillColor: RiseColors.surface2,
                errorText: _wrong ? 'Try again' : null,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(RiseRadii.base),
                  borderSide: BorderSide(
                      color: _wrong ? RiseColors.danger : RiseColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(RiseRadii.base),
                  borderSide: const BorderSide(color: RiseColors.primary),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          PrimaryButton(label: 'Check', onPressed: _submit),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Create the Hold mission**

Create `lib/ui/missions/hold_mission.dart`:

```dart
import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'mission_frame.dart';

Duration holdDurationFor(String diff) {
  switch (diff) {
    case 'hard':
      return const Duration(seconds: 12);
    case 'medium':
      return const Duration(seconds: 8);
    default:
      return const Duration(seconds: 5);
  }
}

class HoldMission extends StatefulWidget {
  const HoldMission({
    super.key,
    required this.diff,
    required this.onSolved,
    this.holdDuration, // injectable for tests
  });

  final String diff;
  final VoidCallback onSolved;
  final Duration? holdDuration;

  @override
  State<HoldMission> createState() => _HoldMissionState();
}

class _HoldMissionState extends State<HoldMission>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: widget.holdDuration ?? holdDurationFor(widget.diff),
    )..addStatusListener((s) {
        if (s == AnimationStatus.completed) widget.onSolved();
      });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _down() => _c.forward();
  void _up() {
    if (_c.status != AnimationStatus.completed) _c.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return MissionFrame(
      instruction: 'Hold the button until it fills',
      child: GestureDetector(
        onTapDown: (_) => _down(),
        onTapUp: (_) => _up(),
        onTapCancel: _up,
        child: SizedBox(
          width: 140,
          height: 140,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 140,
                  height: 140,
                  child: CircularProgressIndicator(
                    value: _c.value,
                    strokeWidth: 8,
                    backgroundColor: RiseColors.surface2,
                    valueColor:
                        const AlwaysStoppedAnimation(RiseColors.primary),
                  ),
                ),
                Container(
                  width: 104,
                  height: 104,
                  decoration: const BoxDecoration(
                      color: RiseColors.primary, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Text('HOLD',
                      style: RiseText.mono(
                          size: 16,
                          weight: FontWeight.w700,
                          color: RiseColors.primaryText)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Create the Tap mission**

Create `lib/ui/missions/tap_mission.dart`:

```dart
import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'mission_frame.dart';

int tapTargetFor(String diff) {
  switch (diff) {
    case 'hard':
      return 50;
    case 'medium':
      return 30;
    default:
      return 15;
  }
}

class TapMission extends StatefulWidget {
  const TapMission({
    super.key,
    required this.diff,
    required this.onSolved,
    this.targetTaps, // injectable for tests
  });

  final String diff;
  final VoidCallback onSolved;
  final int? targetTaps;

  @override
  State<TapMission> createState() => _TapMissionState();
}

class _TapMissionState extends State<TapMission> {
  int _count = 0;
  late final int _target = widget.targetTaps ?? tapTargetFor(widget.diff);

  void _tap() {
    if (_count >= _target) return;
    setState(() => _count++);
    if (_count >= _target) widget.onSolved();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _target - _count;
    return MissionFrame(
      instruction: 'Tap $remaining more time${remaining == 1 ? '' : 's'}',
      child: GestureDetector(
        onTap: _tap,
        child: Container(
          width: 150,
          height: 150,
          decoration: BoxDecoration(
            color: RiseColors.primary,
            borderRadius: BorderRadius.circular(RiseRadii.lg),
            boxShadow: RiseShadows.primary,
          ),
          alignment: Alignment.center,
          child: Text('$remaining',
              style: RiseText.mono(
                  size: 48,
                  weight: FontWeight.w600,
                  color: RiseColors.primaryText)),
        ),
      ),
    );
  }
}
```

- [ ] **Step 7: Create the Memory mission**

Create `lib/ui/missions/memory_mission.dart`:

```dart
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'mission_frame.dart';

int memoryLengthFor(String diff) {
  switch (diff) {
    case 'hard':
      return 5;
    case 'medium':
      return 4;
    default:
      return 3;
  }
}

/// A random pad sequence (pads 0..3). Pass [rng] for determinism in tests.
List<int> generateSequence(int length, [Random? rng]) {
  final r = rng ?? Random();
  return List.generate(length, (_) => r.nextInt(4));
}

class MemoryMission extends StatefulWidget {
  const MemoryMission({
    super.key,
    required this.diff,
    required this.onSolved,
    this.sequence, // injectable for tests
  });

  final String diff;
  final VoidCallback onSolved;
  final List<int>? sequence;

  @override
  State<MemoryMission> createState() => _MemoryMissionState();
}

class _MemoryMissionState extends State<MemoryMission> {
  late List<int> _seq;
  int _flashIndex = -1; // lit pad during playback; -1 = none
  int _inputPos = 0;
  bool _accepting = false;
  final _timers = <Timer>[];

  @override
  void initState() {
    super.initState();
    _seq = widget.sequence ?? generateSequence(memoryLengthFor(widget.diff));
    _play();
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    super.dispose();
  }

  void _play() {
    _accepting = false;
    _inputPos = 0;
    const on = Duration(milliseconds: 420);
    const gap = Duration(milliseconds: 180);
    var t = Duration.zero;
    for (var i = 0; i < _seq.length; i++) {
      final lit = _seq[i];
      _timers.add(Timer(t, () {
        if (mounted) setState(() => _flashIndex = lit);
      }));
      t += on;
      _timers.add(Timer(t, () {
        if (mounted) setState(() => _flashIndex = -1);
      }));
      t += gap;
    }
    _timers.add(Timer(t, () {
      if (mounted) setState(() => _accepting = true);
    }));
  }

  void _replay() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    setState(() {
      _flashIndex = -1;
      _accepting = false;
      _inputPos = 0;
    });
    _play();
  }

  void _tap(int pad) {
    if (!_accepting) return;
    if (pad == _seq[_inputPos]) {
      _inputPos++;
      if (_inputPos >= _seq.length) widget.onSolved();
    } else {
      _replay(); // wrong — show it again
    }
  }

  @override
  Widget build(BuildContext context) {
    return MissionFrame(
      instruction: _accepting ? 'Repeat the sequence' : 'Watch carefully…',
      child: SizedBox(
        width: 200,
        child: GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          children: [
            for (var i = 0; i < 4; i++)
              GestureDetector(
                key: ValueKey('mem-pad-$i'),
                onTap: () => _tap(i),
                child: Container(
                  decoration: BoxDecoration(
                    color: _flashIndex == i
                        ? RiseColors.accent
                        : RiseColors.surface2,
                    borderRadius: BorderRadius.circular(RiseRadii.base),
                    border: Border.all(color: RiseColors.border),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 8: Create the host**

Create `lib/ui/missions/mission_host.dart`:

```dart
import 'package:flutter/widgets.dart';

import '../../domain/alarm.dart';
import 'hold_mission.dart';
import 'math_mission.dart';
import 'memory_mission.dart';
import 'tap_mission.dart';

/// Structurally a `MissionBuilder` (see `ring_screen.dart`): picks the mission
/// widget for [alarm.mission]. `'none'` never reaches here — RingScreen shows
/// slide-to-wake for it — so it maps to an empty box defensively.
Widget buildMission(BuildContext context, Alarm alarm, VoidCallback onSolved) {
  switch (alarm.mission) {
    case 'math':
      return MathMission(diff: alarm.missionDiff, onSolved: onSolved);
    case 'hold':
      return HoldMission(diff: alarm.missionDiff, onSolved: onSolved);
    case 'tap':
      return TapMission(diff: alarm.missionDiff, onSolved: onSolved);
    case 'memory':
      return MemoryMission(diff: alarm.missionDiff, onSolved: onSolved);
    default:
      return const SizedBox.shrink();
  }
}
```

- [ ] **Step 9: Run the missions test to verify it passes**

```bash
flutter test test/ui/missions/missions_test.dart
```
Expected: PASS — 10 tests green. (Uses `pump`, never `pumpAndSettle`.)

- [ ] **Step 10: Run the whole suite and analyze**

```bash
flutter test
flutter analyze
```
Expected: all green; `No issues found!`.

- [ ] **Step 11: Commit**

```bash
git add lib/ui/missions test/ui/missions
git commit -m "feat(ui): add the four wake missions and the mission host"
```

---

## Remaining tasks (Tasks 11–14 — screens; full code just before execution)

Tasks 1–10 above are complete. The remaining screens build on the same components/providers and get full code just before execution: **Task 11** Onboarding, **Task 12** Profile/Settings, **Task 13** the tab-bar app shell (wires Home ↔ Create/Edit navigation and the ToastHost), **Task 14** `main.dart` wiring (swap `DevRingPage`→`RingScreen` with `missionBuilder: buildMission`, `DevHomePage`→`AppShell`) + delete dev screens + device verification.

**Task 7 — Home screen.** Header (greeting + first name + streak pill, avatar), the next-alarm hero card (NEXT ALARM label, big mono time + AM/PM, "{label} · rings in Xh Ym" live countdown via a 1s ticker, animated bell, full-width Preview button that opens the ring screen), and the "Your alarms" list (rows: mono time + AM/PM, "{label} · {repeat}", `DayChips` compact, `RiseSwitch`; tap row → edit). The Crew·live strip is omitted this plan (empty region). Reads `alarmsProvider`; toggling a row calls the mutation. Widget-tested for rendering alarms and the toggle.

**Task 8 — Create/Edit screen.** Sticky Cancel/title/Save header; `TimeDial`; `DayChips` (editable) + `repeatLabel`; label field; `SoundChips` (Sunrise/Chimes/Birdsong/Radar/Cosmic); the mission radio-list (None/Math/Hold/Tap/Memory) with an Easy/Medium/Hard `SegmentedControl` shown only when a mission is selected; Delete (edit only). Sheet-up animation. Save writes via the mutation provider (which reconciles) and pops. Widget-tested: edit an existing alarm, change time via drag, toggle days, save persists.

**Task 9 — Ring screen (replaces DevRingPage).** Full-screen: pulsing bell in an accent-soft well (glow keyframe), giant mono current time + AM/PM (1s ticker), label, `SlideToWake`, and a "Snooze {n} min" button. Wired to the engine: it receives the ringing alarm id (from `main.dart`'s `getRingingAlarmId` poll), and slide-to-wake either dismisses (via `AlarmHostApi().stopRinging(id)` + `recordDismissed` + reconcile, exactly as `DevRingPage` does today) or, if the alarm has a mission, launches the mission host. Snooze re-arms per the snooze policy (Plan 4 owns the budget; this plan does a single fixed snooze). Widget-tested with a fake host API for dismiss; device-verified in Task 14.

**Task 10 — Missions + host.** `MissionHost` picks the overlay for the alarm's `mission`/`missionDiff` and, on completion, dismisses the alarm. The four overlays, faithful to the prototype: **Math** (equation + 3×4 keypad, wrong→red, 1/2/3 problems by difficulty), **Hold** (press-and-hold a conic-fill target ~2s at a random position, respawns; 2/3/4 targets), **Tap** (pop a target at a random position, respawns; 6/9/12), **Memory** (2×2 grid flashes a 3/4/5 sequence, repeat it; wrong replays). Each overlay is self-contained client logic (no backend), unit/widget-tested for its completion condition (e.g. correct math answer advances; full sequence completes).

**Task 11 — Onboarding.** 3 swipe slides (icon-in-black-well + title + body, progress dots + Skip, Next/Get started, back chevron after slide 1) then the sign-in screen ("Continue with Apple" primary, "Continue with phone number" secondary). **Sign-in is a placeholder that proceeds to Home** — real auth is Plan 5. Shown only on first launch (a `SharedPreferences`/Drift flag). Widget-tested for slide advance and finish.

**Task 12 — Profile + Settings.** Avatar + name + streak header; a settings list (bedtime reminder time, default sound, "Let crew wake me" toggle — all local via a settings provider); Sign out (placeholder). Widget-tested for rendering and toggling a local setting.

**Task 13 — App shell + tab bar.** The bottom tab bar (Home · Crew · center + FAB · Sleep · You) with the translucent-white blur treatment; `IndexedStack` tab content; the center FAB opens Create. **Crew and Sleep tabs render a simple "Coming soon" placeholder** (their real screens are Plans 5–7). Navigation: a root navigator (as `main.dart` already uses) so the engine can push the ring screen over everything. Widget-tested for tab switching and the FAB opening Create.

**Task 14 — Wire main.dart + delete dev screens + device verification.** Replace `DevHomePage`/`DevRingPage` in `lib/main.dart` with `AppShell` and the real `RingScreen` (keep the existing `getRingingAlarmId` cold-start/resume poll and the `AlarmSyncService.configureForApp` + reconcile wiring). Wrap the app in a Riverpod `ProviderScope`. Delete `lib/ui/dev_home_page.dart` and `lib/ui/dev_ring_page.dart` and their references. **Verify on the Android emulator and the physical Samsung** (like Plan 1 Task 12): onboard → create an alarm → it appears on Home → set "Ring in ~1 min" via a real alarm → the real ring screen shows over the lock screen → slide-to-wake (through a mission if set) dismisses it. Record results in `docs/superpowers/reliability/`.

---

## Definition of done

- [ ] `flutter test` passes (design-system + screen widget tests + the migration test).
- [ ] `flutter analyze` clean; `flutter build apk --release` succeeds.
- [ ] The dev screens are gone; the real Mono UI replaces them.
- [ ] On device: onboarding → create → Home list → real alarm rings on the designed ring screen → slide-to-wake (via a mission when set) dismisses it.
- [ ] Every screen matches the prototype's Mono tokens (colors, Geist/Geist Mono, radii, shadows, spacing) — spot-checked against `project/Rise.dc.html`.

## What Plan 4 picks up

The reliability/behavior layer on top of this UI: snooze budget (shrinking 9→5→3), wake-up check, escalation ladder, goal-lock, mission chaining, and the Photo/QR/Typing/Shake missions — plus, on iOS, wiring the AlarmKit `secondaryIntent` to open the app for a mission.

