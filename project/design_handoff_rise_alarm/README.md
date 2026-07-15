# Handoff: Rise — Social Alarm App

## Overview
Rise is a mobile (iOS) alarm app with a social layer. Core: create/edit alarms, an alarm‑ringing screen, and **dismiss missions** that force you awake (math, hold, tap, memory). Social: a **Crew** of friends with live sleep/awake status, **groups** of friends, setting alarms for friends/groups, sending a **voice recording** that becomes a friend's alarm sound, and **sleep statistics** with a streak leaderboard.

## About the Design Files
The file in this bundle (`Rise.dc.html`) is a **design reference created in HTML** — an interactive prototype showing the intended look and behavior. It is **not production code to copy directly**. The task is to **recreate these designs in your target codebase** (React Native, SwiftUI, Flutter, etc.) using its established patterns, navigation, and component library. If no environment exists yet, pick the framework best suited to a mobile alarm app (React Native or SwiftUI recommended) and implement there.

> Note on the file format: `Rise.dc.html` is a single-file component. Open it in a browser to click through every flow. The logic lives in a `class Component` block near the bottom; the markup is the template above it. Read it for exact values and behavior — don't port its runtime.

## Fidelity
**High‑fidelity.** Final colors, typography, spacing, and interactions are all specified below and in the file. Recreate the UI to match, using your codebase's primitives. The visual language is "shadcn‑style": light neutral surfaces, near‑black primary buttons, subtle 1px borders, restrained shadows, monospace for all numerals/times.

---

## Design Tokens

### Color (light / "Mono" theme — the only theme)
| Token | Hex | Use |
|---|---|---|
| app background | `#f4f4f5` | screen background |
| surface / card | `#ffffff` | cards, sheets |
| surface‑2 | `#fafafa` | insets, chips, keypad |
| text | `#09090b` | primary text |
| text‑dim | `#71717a` | secondary text |
| text‑faint | `#a1a1aa` | tertiary/placeholder |
| border | `#e4e4e7` | card & control borders |
| divider | `#f0f0f1` | list dividers |
| primary | `#18181b` | primary buttons, active toggles, "today" bar |
| primary‑text | `#fafafa` | text on primary |
| accent | `#18181b` | same as primary (monochrome accent) |
| accent‑soft | `#f4f4f5` | icon wells, highlighted rows, live countdown well |
| danger | `#ef4444` | delete / sign out / wrong answer |
| positive | `#22c55e` | "awake" status dot, positive stat |
| waking | `#f59e0b` | "waking up" status dot |

Friend avatar colors: Maya `#f43f5e`, Sana `#8b5cf6`, Leo `#3b82f6`, Ivy `#f59e0b`, Kojo `#10b981` (white initials).

### Typography
- **UI / display:** Geist (fallback `system-ui, sans-serif`). Display/titles weight 600, letter‑spacing ‑0.02em.
- **Numerals / time / stats:** Geist Mono (fallback `ui-monospace, monospace`), weight 300–600.
- Section labels: 11px, weight 600, letter‑spacing 0.1em, UPPERCASE, text‑dim.
- Body 14–15px; captions 12–13px. Minimum hit target 44px.

### Radius / shadow / spacing
- Radius: sm 9px, base 13px, lg 18px, pill 999px.
- Card shadow: `0 1px 2px rgba(24,24,27,.05), 0 1px 3px rgba(24,24,27,.04)`.
- Primary shadow: `0 1px 2px rgba(0,0,0,.10)`.
- Screen padding 20px; card padding 13–16px; gaps 10–12px.

### Device frame
iPhone: 390×844 screen, 56px outer radius, dynamic‑island pill (118×33, `#000`) centered at top. Status bar 52px tall, time "9:41" left, signal/wifi/battery right. Home indicator bar at bottom. Bottom tab bar is translucent white with blur.

---

## Screens / Views

### 1. Onboarding
3 swipe slides (icon in a circular black well + title + body) with progress dots + Skip, then a sign‑in screen ("Continue with Apple" primary, "Continue with phone number" secondary). Bottom Next / Get started button; back chevron appears after slide 1.

### 2. Home (tab)
- Header: greeting + first name (display), streak pill (flame icon + count), avatar circle.
- **Next‑alarm hero card:** "NEXT ALARM" label, big mono time + AM/PM, "{label} · rings **in Xh Ym**" (live countdown, accent), animated bell icon in an accent‑soft well, full‑width **Preview alarm** primary button (opens the ringing screen).
- **Crew · live** strip: green pulsing dot + "See all". Horizontal cards of friends about to wake — avatar w/ status dot, name, status, live `m:ss` countdown, Nudge button.
- **Your alarms:** "New" button (opens create). Rows: mono time + AM/PM, optional voice badge, "{label} · {repeat}", weekday chips (S M T W T F S; active = accent‑soft), toggle switch (on = primary). Tap row → edit.

### 3. Create / Edit alarm
Sticky header: Cancel / title / Save (or Send). Optional recipient chip when setting for a friend/group.
- **Time picker:** big mono HH : MM with up/down chevrons; drag the number vertically to change (pointer drag, ~7px per step, wraps). AM/PM vertical segmented toggle.
- **Repeat:** 7 weekday buttons; label below ("Weekdays", "Weekends", "Every day", or list).
- **Label** text field; **Sound** chips (Sunrise, Chimes, Birdsong, Radar, Cosmic).
- **Dismiss mission** (see below): radio‑list of None / Math / Hold / Tap / Memory + Easy/Medium/Hard difficulty segmented (hidden when None).
- Friend variant adds a Note field + "Attach a voice recording" button.
- Edit variant adds a red "Delete alarm".

### 4. Ringing screen (full overlay)
Full‑screen. Pulsing bell in accent‑soft well (glow keyframe), giant mono current time + AM/PM, alarm label. If the alarm is a friend's voice alarm, a chip: avatar + "{Name} recorded your alarm" + animated waveform. **Snooze {n} min** button + **Slide to wake up →** track (draggable knob; ≥97% triggers wake). If the alarm has a mission, sliding launches the mission overlay instead of dismissing.

### 5. Mission overlay (full overlay) — the "unavoidable wake" feature
Header: mission title + Snooze. One of:
- **Math:** progress "done / total", equation "A op B =", input box (turns red on wrong), 3×4 keypad (1‑9, ⌫, 0, ✓). Correct answer advances; total 1/2/3 by difficulty.
- **Hold:** instruction + progress; a circular target at a **random position**; press‑and‑hold fills a conic ring (~2s); releasing early resets it; each completion respawns the target elsewhere. 2/3/4 targets.
- **Tap:** a target dot appears at a **random position**; tap to pop, respawns elsewhere. 6/9/12 targets.
- **Memory:** 2×2 tile grid flashes a sequence, then the user repeats it; a wrong tap replays. Sequence length 3/4/5.
Completing the mission dismisses the alarm ("Good morning" toast). Snooze exits at any time.

### 6. Crew (tab) — Friends / Groups segmented
- **Friends:** two stat cards (Awake now / Still asleep) + friend rows (avatar + status dot, name, streak, live status/countdown, Nudge). "Add friends" dashed button.
- **Groups:** group cards (name, chevron, stacked member avatars, "{n} members · {k} awake now"). "New group" dashed button. Header + button becomes "new group" on this tab.

### 7. Friend detail
Back header, large avatar + status, streak / usual‑wake stats, **Set an alarm** (primary) + **Voice alarm** (secondary) actions, and a read‑only list of their alarms.

### 8. Group detail
Back header, group name + "{n} members · {k} awake now", **Wake the group** (primary → create alarm for group) + **Nudge all**, Members list (tap → friend), **Manage** → member picker (all friends with checkmark toggles; add/remove updates the group live).

### 9. New group
Cancel / "New group" / Create. Name field + friend picker (checkmark toggles). Create is disabled until a name is entered.

### 10. Voice recorder (ping)
"Recording an alarm for {Name}", mono timer, animated waveform bars, big mic button (tap to record, up to 15s, glow while recording). After recording: play/pause + re‑record, "Send as {Name}'s alarm" primary. Sending shows a confirmation toast; the clip becomes that friend's alarm sound.

### 11. Sleep stats (tab)
Avg sleep (big mono + delta), consistency ring (conic gradient %), 7‑night hours bar chart (today highlighted in primary), Sleep debt + Wake‑vs‑set cards, weekly snooze mini‑bars, and a **streak leaderboard** (ranked avatars + flame counts; "you" row highlighted).

### 12. Profile (tab)
Avatar + name + streak, Settings list (bedtime reminder, default sound, "Let crew wake me" toggle), Sign out.

### Bottom tab bar
Home · Crew · center **+** FAB (new alarm) · Sleep · You. Active tab = accent, inactive = text‑faint.

---

## Interactions & Behavior
- **Navigation:** stack with back; tabs reset the stack. Ringing, mission, create, ping, group‑new, manage are pushed/overlay views (tab bar hidden on onboarding/create/ping/mission/new‑group/manage).
- **Live status (setInterval, 1s):** friend countdowns tick down; when one hits 0 the friend flips asleep → **waking** (≈5s) → **awake**, and a toast fires ("{Name} just woke up"). Two friends are seeded to wake ~45s and ~80s after launch to demo this.
- **Toggles/switches** animate (translateX 0↔18px, 0.2s). Toasts auto‑hide ~2.7s.
- **Time picker** supports chevrons and vertical pointer‑drag; values wrap.
- **Slide‑to‑wake** uses pointer capture; fill and knob track the drag; snap back if released < 97%.
- **Missions** use random on‑screen positions (`x: 6–72%`, `y: 18–70%`), hold uses a 50ms interval filling to 100, memory uses timed sequence playback.
- Animations: aurora is disabled in this theme; keep bell‑swing, glow pulse, waveform, pop‑in, sheet‑up, toast‑up, status‑dot pulse.

## State Management
Per‑screen/global state observed in the prototype:
- `screen`, nav `stack`; `tab`/derived active tab.
- `alarms[]` `{id,h,m,ampm,label,days[0‑6],on,sound,mission,missionDiff,voice?,from?}`.
- `friends[]` `{id,name,initials,color,status:'asleep'|'waking'|'awake',nextTs,wake,streak,alarms[]}`.
- `groups[]` `{id,name,memberIds[]}`; `crewTab`, `selGroup`, `newGroup{name,members[]}`.
- `draft` (create form incl. `forFriend`/`forGroup`), `editId`.
- `ringing`, `slide` (0‑1), `mission` (type‑specific runtime), `rec` (recorder), `snoozeTotal`, `toast`.

## Tweakable options (props in the prototype)
- `liveDemo` (bool) — enable the auto wake‑up demo.
- `snoozeMinutes` (int, 1‑30) — snooze duration shown/added.

## Assets
- Fonts: **Geist** + **Geist Mono** (Google Fonts). Substitute your app's system/brand font if needed.
- All icons are inline SVG (line icons, `currentColor`) — bell, people, home, chart, person, mic, plus, chevrons, flame, check, bolt/nudge, play/pause. No raster assets. Recreate with your icon set (e.g. SF Symbols / Lucide).
- No third‑party images. Real user photos/voice are not included (recorder is simulated).

## Files
- `Rise.dc.html` — the full interactive prototype (all screens + logic). Open in a browser to explore every flow before implementing.
