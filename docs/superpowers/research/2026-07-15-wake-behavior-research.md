# Rise — The Science of Waking Up: Research Report

**Date:** 2026-07-15
**Purpose:** Evidence base for the Rise design spec (`../specs/2026-07-15-rise-alarm-app-design.md`). Confidence grades reflect study quality and directness. Contested points are flagged rather than papered over — several popular "wake-up app" premises are weaker than the marketing implies.

---

## 1. Sleep inertia — the grogginess we're actually fighting

**F1. Sleep inertia is a real neurophysiological state, not laziness.** Impaired alertness, disorientation, degraded cognition immediately post-waking; EEG shows persistent sleep-like delta activity, prefrontal/executive regions recover slowest, reduced cerebral blood flow up to ~30 min. **Confidence: High.** https://pmc.ncbi.nlm.nih.gov/articles/PMC6710480/ (Hilditch & McHill, *Nature and Science of Sleep* 2019)

**F2. Worst in the first 15–30 minutes; can linger.** Bulk of impairment in first 30 min; subjective alertness recovers over ~1–2 h; objective performance up to ~3.5–4 h (saturating-exponential decay). **Confidence: High.** Same source.

**F3. The immediate deficit can exceed all-nighter-level impairment.** Performance in the first minutes after 8 h sleep can exceed the deficit from 26 h total sleep deprivation. **Confidence: Medium** (striking; n=9). Wertz et al., *JAMA* 2006, via PMC6710480.

**F4. "Waking from deep sleep is worst" is contested.** Mechanistic consensus and some data support N3-worst (~41% performance drop from SWS vs little from N2); however several studies found no association between wake stage and performance, and inertia is worst when waking during your *biological night* regardless of stage. Undercuts the "wake me only from light sleep" premise. **Confidence: Medium / contested.** https://pmc.ncbi.nlm.nih.gov/articles/PMC3130065/ · https://pmc.ncbi.nlm.nih.gov/articles/PMC5337178/

**F5. The 0–15 min window is nearly untreatable reactively.** No post-waking countermeasure (bright light, caffeine, face-washing) reliably improved objective performance in the first ~15 min. **Confidence: High.** https://pmc.ncbi.nlm.nih.gov/articles/PMC5136610/

**F6. Caffeine works only proactively** (~200 mg before a 15–20 min nap); post-waking caffeine misses the worst window (onset ~20–30 min). **Confidence: High.** Same source.

**F7. Light improves *subjective* alertness more than *objective* cognition** at morning wake times; more potent when waking during the biological night. **Confidence: High.** Same source.

**F8. Dawn simulation (~250–300 lux over final ~30 min): modest, mostly subjective benefit.** One RCT (n=16) reduced subjective sleepiness, no performance/cortisol effect; a smaller RCT (n=8) did find performance gains. **Confidence: Medium.** https://pubmed.ncbi.nlm.nih.gov/20408928/

**F9. Movement, temperature, and cognitive-load countermeasures are essentially untested.** No controlled study validates exercise-on-waking, temperature manipulation, or math-puzzle dismissal as inertia reducers. **Confidence: High that the gap exists.** https://pmc.ncbi.nlm.nih.gov/articles/PMC7155753/

---

## 2. Snooze psychology — the honest picture is de-escalatory

**F10. Snoozing is majority behavior.** Largest dataset (21,222 users, 3M+ sessions): **55.6% of sessions end with a snooze**, avg 2.4 presses / 10.8 min; **45.2% are heavy snoozers** (>80% of mornings). A wearable cohort independently found ~57% habitual snoozers. **Confidence: High.** https://pmc.ncbi.nlm.nih.gov/articles/PMC12089427/ · https://academic.oup.com/sleep/article/45/10/zsac184/6661272

**F11. Snoozers skew young, female, evening-chronotype, sleep-deprived, less active.** Each +1,000 daily steps → ~11% lower snoozing odds; snoozing peaks on weekdays. This is Rise's core user — shaming them would misfire. **Confidence: High.** Same sources.

**F12. A bounded ~30-min snooze does NOT clearly harm you, and may modestly help.** Sundelin et al. (survey n=1,732 + PSG lab n=31): 30 min of snoozing cost ~6 min of sleep, produced *slightly better* cognition on rising, no clear negative effect on cortisol/mood/sleepiness, and avoided forced awakening from deep SWS. **Confidence: Medium–High.** https://onlinelibrary.wiley.com/doi/10.1111/jsr.14054 (paywalled; corroborated https://www.sciencedaily.com/releases/2023/10/231018115711.htm)

**F13. But the harm question is contested.** An earlier controlled study found snooze alarms prolong inertia via repeated forced awakenings; wearable data show habitual snoozers have lighter final-hour sleep (+2.19%) and modestly higher heart rate. **Confidence: Medium.** https://pmc.ncbi.nlm.nih.gov/articles/PMC9804954/

**Design implication:** Rise's anti-snooze proposition is **behavioral (getting up on time for your goals), not "snoozing is destroying your health."**

---

## 3. Behavioral design — what actually changes behavior

**F14. Loss aversion is real (~2×) but a 2025 re-analysis contests universality.** λ ≈ 1.96. **Confidence: High for the mean.** https://www.aeaweb.org/articles?id=10.1257%2Fjel.20221698

**F15. Money stakes: largest per-user effect, crushed uptake.** Loss-framed money raised step-goal achievement 30%→45% of days; but when offered, only ~13.7% accepted deposits vs 90% rewards — rewards won on intention-to-treat. **Confidence: High.** https://www.acpjournals.org/doi/10.7326/M15-1635 · https://pmc.ncbi.nlm.nih.gov/articles/PMC4471993/ → **Default to rewards/streaks; money stakes opt-in only.**

**F16. Social competition beats support and collaboration for sustained behavior.** 602-person step RCT: competition +920 steps/day, only arm still significant at follow-up. **Confidence: High.** https://jamanetwork.com/journals/jamainternalmedicine/fullarticle/2749761

**F17. Public commitment can backfire for identity goals, not behavioral ones.** Identity-level intentions ("I'm a morning person") reduced follow-through via premature "sense of completeness"; specific behavioral commitments don't. **Confidence: Medium.** https://journals.sagepub.com/doi/10.1111/j.1467-9280.2009.02336.x → **Frame accountability around the action.**

**F18. Streaks work — and forgiveness makes them work better.** Duolingo: 7-day-streak users 3.6× more likely to finish; *doubling* streak-freezes raised DAU; decoupling streaks from daily goals raised D14 retention +3.3%. Missing one day doesn't hurt habit formation — quitting after does. Habits plateau at median 66 days. **Confidence: Medium.** https://blog.duolingo.com/improving-the-streak/ · https://www.researchgate.net/publication/32898894

**F19. Gamification has a small-to-medium real effect.** Hedges g ≈ 0.42; ~+489 steps/day gamified vs not. Real but modest. **Confidence: High (positive), Medium (magnitude).** https://www.jmir.org/2022/1/e26779

**F20. Variable-ratio rewards: strongest engagement schedule, biggest ethical hazard.** Robust mechanism; thin direct wellbeing-app RCT evidence; documented compulsive-use downside in younger users. **Confidence: High (mechanism), Low (app effect).**

**F21. Friction/nudge effects are smaller than headlines.** Nudge meta d=0.43 → d≈0.03–0.31 after publication-bias correction. **Confidence: High.** https://www.pnas.org/doi/10.1073/pnas.2200300119

**F22. No peer-reviewed RCT shows mission-based dismissal reduces oversleeping.** All effectiveness evidence is company/app-store data. An evidence gap Rise could own. **Confidence: High (that evidence is absent).** https://www.mdpi.com/2076-3417/10/11/3993

---

## 4. What actually gets people out of bed (sensory levers)

**F23. Sound design is the most app-actionable lever; melodic beats harsh.** Melodic tones associated with less perceived inertia; harsh "beep-beep" with more (McFarlane 2020, N=50, Cramér's V=0.37). Follow-up: melodic/rhythmic improved objective vigilance. **Confidence: Medium.** https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0215788

**F24. A loved one's voice is dramatically more effective — for children.** Mother's voice woke **86–91% of children (5–12) vs 53%** for tone; escape 84–86% vs 51%; median time-to-escape **18–28 s vs 282 s**. Child's own name not necessary. **Confidence: High** (n=176). https://pediatricsnationwide.org/2018/11/06/smoke-alarms-using-mothers-voice-wake-children-better-than-high-pitch-tone-alarms/

**F25. The voice advantage does NOT generalize to older adults.** Voice alarm poor for older adults (7.5% failed to wake at 95 dBA); mixed-frequency low signal best. **Confidence: Medium–High.** https://link.springer.com/article/10.1007/s10694-007-0017-5

**F26. Low-frequency 520 Hz square-wave signals wake far better.** ~92% of hard-of-hearing adults at ≤75 dB; ~4–12× more effective than high-pitch for children/heavy sleepers/hearing-impaired; mandated by NFPA 72 for sleeping areas. Frequency and melodicity matter more than volume. **Confidence: High.** https://www.jensenhughes.com/insights/single-and-multi-station-low-frequency-audible-signaling

**F27. Vibration/haptics is the most reliable non-auditory waker + accessibility necessity.** Bed/pillow shakers woke ~95% of deaf adults within 4 min; wrist vibrotactile ~100% EEG arousal; intermittent beats continuous; multi-sensory stacking most robust. **Confidence: Medium–High.** https://link.springer.com/article/10.1007/s10694-022-01265-8

**F28. Smell/scent alarms don't work.** Olfaction is suppressed during sleep — even H₂S up to 8 ppm produced no arousal increase. Only trigeminal irritants wake people. **Confidence: High.** https://academic.oup.com/sleep/article/30/4/506/2708213

**F29. Movement/cognitive missions are unvalidated — and cognitive tasks fight the brain at its weakest.** Alertness/attention are the most impaired domains right after waking. Missions are plausible engagement/anti-snooze devices, not proven inertia cures. **Confidence: Medium.** https://journals.plos.org/plosone/article?id=10.1371%2Fjournal.pone.0079688

---

## 5. Chronotypes & circadian — the highest-leverage habit

**F30. Consistent wake time is the strongest evidence-backed lever.** Higher Sleep Regularity Index → **~30–48% lower all-cause mortality** (HR 0.52 minimal / 0.70 fully adjusted); **SRI predicts mortality more strongly than duration** (UK Biobank, n=60,977, 6.3 yr). **Confidence: High.** https://pmc.ncbi.nlm.nih.gov/articles/PMC10782501/

**F31. Wake difficulty is partly biology.** Adolescents phase-delay; older adults phase-advance. Evening chronotypes suffer more inertia largely because they're woken during their biological night. **Confidence: High (age/chronotype).** https://www.frontiersin.org/journals/psychiatry/articles/10.3389/fpsyt.2022.785079/full

**F32. Social jetlag is widespread.** ~70% of adults have ≥1 h and 30–50% have ≥2 h workday-vs-freeday misalignment. **Confidence: Medium.** https://pmc.ncbi.nlm.nih.gov/articles/PMC8707256/

**F33. Consumer "smart wake windows" rest on weak evidence.** Devices detect sleep-vs-wake ~85–95% vs PSG but classify *stages* only ~60–85% (phone motion-only ~65%). The one controlled test of a stage-triggered "smart" alarm found **no overall benefit**. **Confidence: High (accuracy), Medium (null result).** https://pmc.ncbi.nlm.nih.gov/articles/PMC8120339/ · https://pmc.ncbi.nlm.nih.gov/articles/PMC10969141/

---

## 6. Failure modes

**F34. Alarm-tone habituation: real as a principle, under-evidenced for alarms specifically.** A systematic review found no habituation evidence in its studies. Sound rotation is a cheap hedge — don't market as proven. **Confidence: Low–Medium.** https://pmc.ncbi.nlm.nih.gov/articles/PMC7711682/

**F35. High-frequency hearing loss makes high-pitched alarms fail; low-frequency stays audible.** **Confidence: High.**

**F36. Difficulty waking is a real clinical feature.** Severe sleep inertia in 36–66% of idiopathic hypersomnia patients; hypersomnolence in ~25% of major-depression patients. **Confidence: High.** https://pmc.ncbi.nlm.nih.gov/articles/PMC5337178/

**F37. "Alarm across the room" is practitioner lore, not trial-validated.** **Confidence: Low.**

---

## 7. Ethics & safety

**F38. Abrupt forced waking increases the morning blood-pressure surge** vs natural waking (pilot, n=32) → gradual-onset defaults. **Confidence: Medium.** https://www.sciencedirect.com/science/article/abs/pii/S0147956324001195

**F39. Shift workers (~20% of workforce) have circadian misalignment; aggressive alarms treat the symptom.** **Confidence: High (health risks).** https://pmc.ncbi.nlm.nih.gov/articles/PMC6859247/

**F40. Missions run during measurably impaired cognition** (15–30 min, up to 1 h) — relevant if the user then drives, or has cardiac/balance conditions during physical missions. No controlled safety data on mission alarms. **Confidence: Low (inference).**

---

## What we are NOT confident about (label honestly in-product)

- That a phone/wrist alarm reliably knows you're in "light sleep" (F33), or that light-sleep waking reduces grogginess (F4). **Both contested** — don't build the core promise on smart wake.
- That snoozing meaningfully harms health (F12/F13). **Contested, leaning "not very harmful."**
- That missions, movement, or math *reduce sleep inertia* (F9/F29). **Unvalidated.**
- That alarm-tone habituation is a proven, quantified effect (F34). **Principle yes, alarm-specific no.**
- That across-the-room placement works (F37). **Lore.**

---

## Prioritized product recommendations

### Tier 1 — Strong evidence, high leverage

1. **Make consistent wake time the product's spine.** Regularity beats duration (F30). Hero metric = regularity streak; discourage large weekday/weekend swings (F32).
2. **Ship a low-frequency (~520 Hz) + melodic, gradual-onset alarm engine as default** (F26, F23, F35). Highest-confidence sensory intervention.
3. **Multi-sensory waking: sound + vibration + light, escalating** (F27). The robust path to "100%" and the accessibility path for deaf/HoH users.
4. **Streaks + rewards + social competition by default; money stakes opt-in "hard mode"** (F18, F16, F15). Frame accountability around the action, not identity (F17).

### Tier 2 — Good evidence with caveats

5. **Dawn simulation as a mood/subjective-alertness feature — marketed honestly** (F7, F8): "feel less groggy," not "perform better."
6. **Loved-one's-voice alarm targeted at younger users** (F24, F25). High emotional differentiation for a young, evening-chronotype base (F11).
7. **Rotate sounds as a habituation hedge — don't overclaim** (F34).
8. **Reframe anti-snooze as behavioral, not health-scare** (F12). Structured snooze (bounded budget → escalation) beats absolute blocking; snoozers are the majority (F10, F11).

### Tier 3 — Engagement levers with weak scientific backing

9. **Missions = anti-snooze friction and engagement, not a promised inertia cure** (F22, F29). Rise can generate the missing evidence via A/B tests. Keep optional; escalate gently.
10. **Treat smart-wake windows as nice-to-have and label experimental — or skip** (F33). Circadian consistency is the better bet.

### Cross-cutting guardrails

11. **Gradual-onset default, not jarring blast** (F38).
12. **Gentle / clinical / shift-worker mode** disabling aggressive missions and stakes (F36, F39); signpost that persistent severe difficulty waking can be medical.
13. **Safety interlocks on missions** (F40): never trap the user; always provide an escape that ends the alarm.

---

**Sourcing note:** Primarily peer-reviewed sleep-medicine reviews (Hilditch & McHill 2019; Hilditch et al. 2016; Trotti 2017), two large real-world datasets (*Scientific Reports* 2025 n=21,222; *SLEEP* 2022 n=450), the UK Biobank SRI cohort (n=60,977), behavioral-economics RCTs (Patel, Halpern, Charness & Gneezy), and fire-safety awakening research (Smith & Splaingard; Bruck & Thomas). Weakest evidence explicitly flagged: McFarlane melodic-alarm survey (N=50, self-report), Duolingo self-reported A/B data, all mission-alarm effectiveness claims. Sundelin snooze primary was paywalled but corroborated across independent secondary sources.
