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
## Remaining tasks (specified; full code written in the next authoring pass)

The design-system foundation above (Tasks 1–4) is complete and independently executable. The rest of the plan is scoped below — each will get the same complete-code + TDD treatment. They are grouped so the plan can, if desired, be executed as two sub-projects (**3a: foundation** = Tasks 1–6; **3b: screens** = Tasks 7–14).

**Task 5 — Interactions: TimeDial, SlideToWake, ToastHost.** The draggable `HH : MM` picker (chevrons + vertical pointer-drag ~7px/step, wraps, AM/PM segmented) and the slide-to-wake track (pointer capture, fill+knob track the drag, ≥97% triggers, snaps back below). `ToastHost` overlay auto-hiding ~2.7s. Widget-tested for drag stepping, wrap, and the 97% threshold.

**Task 6 — State layer + Alarm mission fields + DB migration.** Add `mission` (`'none'|'math'|'hold'|'tap'|'memory'`) and `missionDiff` (`'easy'|'medium'|'hard'`) to the `Alarm` entity and the Drift `Alarms` table, with a **schemaVersion 1→2 migration** (`addColumn`) so existing installs upgrade rather than wipe. Riverpod (2.x) providers over the existing `AlarmRepository`/`AlarmSyncService`: `alarmsProvider` (`StreamProvider` over `watchAll`), `alarmMutationsProvider` (upsert/delete/toggle → each calls `AlarmSyncService.reconcileNow()`), `draftProvider` (create/edit form state), `toastProvider`. Unit-tested against an in-memory DB (like Plan 1 Task 5), including the migration.

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

