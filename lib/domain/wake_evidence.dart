import 'wake_event.dart';

/// The emotional colour of a single wake signal (and of the whole card). Pure —
/// the UI maps these to icon + colour so the domain stays Flutter-free.
enum EvidenceTone { good, warn, bad, neutral }

/// One line on the wake-evidence card: a named signal about how the user woke,
/// its short human detail, and how it reads.
class EvidenceSignal {
  const EvidenceSignal({
    required this.label,
    required this.detail,
    required this.tone,
  });

  /// The signal name, e.g. 'On time', 'Left home', 'Alertness'.
  final String label;

  /// A short human value, e.g. 'Up 3 min early', 'Out the door', '82/100'.
  final String detail;

  final EvidenceTone tone;

  @override
  bool operator ==(Object other) =>
      other is EvidenceSignal &&
      other.label == label &&
      other.detail == detail &&
      other.tone == tone;

  @override
  int get hashCode => Object.hash(label, detail, tone);

  @override
  String toString() => 'EvidenceSignal($label: $detail, $tone)';
}

/// A retrospective read on a single morning: the many small signals from one
/// [WakeEvent] (plus the opt-in left-home evidence) fused into a warm verdict
/// and a 0–100 score. This is the "did they actually wake up?" user card the
/// wake engine surfaces — it explains itself, signal by signal, and never
/// shames (the lowest verdict is gentle, not a scolding).
///
/// Pure and deterministic: no clock, no I/O. Construct with [WakeEvidence.of].
class WakeEvidence {
  const WakeEvidence({
    required this.score,
    required this.verdict,
    required this.blurb,
    required this.tone,
    required this.signals,
  });

  /// 0–100 composite. Higher = stronger evidence of a real, clean wake-up.
  final int score;

  /// The short headline, e.g. 'Clean wake-up'.
  final String verdict;

  /// One warm sentence under the verdict.
  final String blurb;

  /// The overall tone (drives the card's accent).
  final EvidenceTone tone;

  /// The individual signals, most reassuring first.
  final List<EvidenceSignal> signals;

  /// Builds the evidence for the most recent COMPLETED wake, or null when there
  /// is nothing to summarise yet (no event, or the latest is still open).
  ///
  /// [leftHome] is today's opt-in left-home verdict (see `leftHomeTodayProvider`)
  /// — true is powerful proof of a real wake-up. It only ever helps the score;
  /// false/absent is treated as "no signal", never as evidence of oversleeping.
  static WakeEvidence? of(WakeEvent? event, {bool leftHome = false}) {
    if (event == null || event.isOpen) return null;

    final signals = <EvidenceSignal>[];
    var score = 50;

    // --- On time -------------------------------------------------------------
    if (event.onTime) {
      score += 20;
      final delta = event.timeToWake;
      signals.add(EvidenceSignal(
        label: 'On time',
        detail: _timingDetail(delta, onTime: true),
        tone: EvidenceTone.good,
      ));
    } else {
      score -= 10;
      signals.add(EvidenceSignal(
        label: 'Woke late',
        detail: _timingDetail(event.timeToWake, onTime: false),
        tone: EvidenceTone.warn,
      ));
    }

    // --- Left home (opt-in, strongest single "genuinely up" proof) -----------
    if (leftHome) {
      score += 20;
      signals.add(const EvidenceSignal(
        label: 'Left home',
        detail: 'Up and out the door',
        tone: EvidenceTone.good,
      ));
    }

    // --- How they got up -----------------------------------------------------
    switch (event.method) {
      case 'mission':
        score += 15;
        signals.add(const EvidenceSignal(
          label: 'Mission',
          detail: 'Solved to dismiss',
          tone: EvidenceTone.good,
        ));
      case 'safety':
        score -= 20;
        signals.add(const EvidenceSignal(
          label: 'Safety dismiss',
          detail: 'Fell back to the safety exit',
          tone: EvidenceTone.bad,
        ));
      case 'slide':
        score += 5;
        signals.add(const EvidenceSignal(
          label: 'Slid to wake',
          detail: 'Dismissed by slide',
          tone: EvidenceTone.neutral,
        ));
      default:
        break; // unknown/none — no signal
    }

    // --- Snoozes -------------------------------------------------------------
    if (event.snoozeCount > 0) {
      score -= (event.snoozeCount * 8).clamp(0, 24);
      signals.add(EvidenceSignal(
        label: 'Snoozes',
        detail: event.snoozeCount == 1
            ? 'One snooze'
            : '${event.snoozeCount} snoozes',
        tone: event.snoozeCount >= 3 ? EvidenceTone.bad : EvidenceTone.warn,
      ));
    } else {
      signals.add(const EvidenceSignal(
        label: 'No snoozes',
        detail: 'Straight up, no snooze',
        tone: EvidenceTone.good,
      ));
    }

    // --- Mission stumbles ----------------------------------------------------
    if (event.missionFailures > 0) {
      score -= (event.missionFailures * 5).clamp(0, 15);
      signals.add(EvidenceSignal(
        label: 'Mission slips',
        detail: event.missionFailures == 1
            ? 'One wrong answer'
            : '${event.missionFailures} wrong answers',
        tone: EvidenceTone.warn,
      ));
    }

    // --- Alertness (PVT reaction speed, present only for the PVT mission) -----
    final a = event.alertnessScore;
    if (a != null) {
      score += ((a - 50) * 0.3).round(); // −15..+15
      signals.add(EvidenceSignal(
        label: 'Alertness',
        detail: '$a/100',
        tone: a >= 70
            ? EvidenceTone.good
            : (a >= 40 ? EvidenceTone.warn : EvidenceTone.bad),
      ));
    }

    score = score.clamp(0, 100);
    final (verdict, blurb, tone) = _verdict(score, leftHome: leftHome);
    // Most reassuring first so the card opens on a high note.
    signals.sort((x, y) => _toneRank(x.tone).compareTo(_toneRank(y.tone)));
    return WakeEvidence(
      score: score,
      verdict: verdict,
      blurb: blurb,
      tone: tone,
      signals: signals,
    );
  }

  static (String, String, EvidenceTone) _verdict(int score,
      {required bool leftHome}) {
    if (score >= 80) {
      return (
        'Clean wake-up',
        leftHome
            ? 'Up, out, and moving — no doubt you\'re awake.'
            : 'Strong signals all round. This is how it\'s done.',
        EvidenceTone.good,
      );
    }
    if (score >= 60) {
      return (
        'You\'re up',
        'Solid morning — the evidence says you\'re properly awake.',
        EvidenceTone.good,
      );
    }
    if (score >= 40) {
      return (
        'Up, a little groggy',
        'You made it out of bed — a bit of light and water will finish the job.',
        EvidenceTone.warn,
      );
    }
    return (
      'Rough morning',
      'You got there in the end. Tomorrow\'s a fresh start.',
      EvidenceTone.bad,
    );
  }

  /// Reassuring (good) first, then neutral, warn, and bad last.
  static int _toneRank(EvidenceTone t) => switch (t) {
        EvidenceTone.good => 0,
        EvidenceTone.neutral => 1,
        EvidenceTone.warn => 2,
        EvidenceTone.bad => 3,
      };

  static String _timingDetail(Duration? d, {required bool onTime}) {
    if (d == null) return onTime ? 'Up on schedule' : 'Up behind schedule';
    final mins = d.inMinutes;
    if (onTime) {
      if (mins <= 0) return 'Up right on time';
      return 'Up within $mins min';
    }
    if (mins <= 60) return '$mins min late';
    final h = mins ~/ 60;
    final m = mins % 60;
    return m == 0 ? '${h}h late' : '${h}h ${m}m late';
  }
}
