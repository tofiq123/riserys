/// The pure model behind the Setup Guardian: the set of checks that decide
/// whether an alarm will actually fire, each reduced to a plain status with
/// human copy, plus an overall summary. No Flutter, no platform channels —
/// the screen feeds this the raw permission booleans and renders the result,
/// and the "Fix" wiring lives in the UI keyed by [ReliabilityCheckId].
library;

/// A single check's state. [unknown] is deliberate and honest: some risks
/// (OEM autostart/background limits) cannot be read by any API, so they degrade
/// to guidance rather than a fabricated pass/fail.
enum ReliabilityStatus { ok, needsAttention, unknown }

/// Identifies each check so the UI can map it to a "Fix" action. The domain
/// never performs the action — it only names it.
enum ReliabilityCheckId {
  notifications,
  exactAlarm,
  battery,
  fullScreenIntent,
  oemAutostart,
}

/// One reliability check: its [id] (for the Fix wiring), a [title], the
/// plain-language [why] it matters, and the current [status].
class ReliabilityCheck {
  const ReliabilityCheck({
    required this.id,
    required this.title,
    required this.why,
    required this.status,
  });

  final ReliabilityCheckId id;
  final String title;
  final String why;
  final ReliabilityStatus status;

  bool get isOk => status == ReliabilityStatus.ok;
  bool get needsAttention => status == ReliabilityStatus.needsAttention;
  bool get isUnknown => status == ReliabilityStatus.unknown;
}

/// Builds the ordered list of checks from the raw permission booleans plus the
/// platform. Android-only concerns (battery optimisation, OEM autostart) are
/// omitted on other platforms so the list never shows an irrelevant row.
///
/// [manufacturer] only affects copy the UI layers on; the pure list is the same
/// regardless, so this signature stays small and easy to test.
List<ReliabilityCheck> buildReliabilityChecks({
  required bool isAndroid,
  required bool notifications,
  required bool exactAlarm,
  required bool fullScreenIntent,
  required bool batteryUnrestricted,
}) {
  ReliabilityStatus flag(bool granted) =>
      granted ? ReliabilityStatus.ok : ReliabilityStatus.needsAttention;

  return [
    ReliabilityCheck(
      id: ReliabilityCheckId.notifications,
      title: 'Notifications',
      why: 'So your alarm can ring and show up — even on silent.',
      status: flag(notifications),
    ),
    ReliabilityCheck(
      id: ReliabilityCheckId.exactAlarm,
      title: 'Exact alarm',
      why: 'So it goes off right on time, not minutes late.',
      status: flag(exactAlarm),
    ),
    ReliabilityCheck(
      id: ReliabilityCheckId.fullScreenIntent,
      title: 'Full-screen alarm',
      why: 'So it fills the screen and wakes you, even when locked.',
      status: flag(fullScreenIntent),
    ),
    if (isAndroid)
      ReliabilityCheck(
        id: ReliabilityCheckId.battery,
        title: 'Unrestricted battery',
        why: 'So the system never quietly sleeps your alarm overnight.',
        status: flag(batteryUnrestricted),
      ),
    if (isAndroid)
      const ReliabilityCheck(
        id: ReliabilityCheckId.oemAutostart,
        title: 'Auto-start & background limits',
        // Undetectable by any API — always surfaced as guidance, never a
        // fabricated pass.
        why: 'Some phones block apps from starting on their own or running in '
            'the background. Rise can\'t check this for you.',
        status: ReliabilityStatus.unknown,
      ),
  ];
}

/// An overall read of a check list: counts, a 0–100 score, and one-line copy.
/// The score is computed over the checks with a *definite* status (ok vs
/// needsAttention); [unknown] items don't drag the score down, they surface as
/// guidance — so a fully-granted phone still reads as ready even with an
/// unknowable OEM check present.
class ReliabilitySummary {
  const ReliabilitySummary(this.checks);

  final List<ReliabilityCheck> checks;

  int get okCount => checks.where((c) => c.isOk).length;
  int get attentionCount => checks.where((c) => c.needsAttention).length;
  int get unknownCount => checks.where((c) => c.isUnknown).length;

  /// Checks that resolved to a real pass/fail (excludes [unknown]).
  int get _definiteTotal => okCount + attentionCount;

  /// 0–100 over the definite checks. Empty or all-unknown lists read as 100
  /// (nothing is known to be wrong).
  int get score => _definiteTotal == 0
      ? 100
      : ((okCount / _definiteTotal) * 100).round();

  /// True when nothing needs the user's attention. Unknown items don't block
  /// this — they're guidance, not failures.
  bool get allClear => attentionCount == 0;

  ReliabilityStatus get overall {
    if (attentionCount > 0) return ReliabilityStatus.needsAttention;
    if (unknownCount > 0) return ReliabilityStatus.unknown;
    return ReliabilityStatus.ok;
  }

  /// A short status line for the dashboard header.
  String get headline {
    if (attentionCount > 0) {
      return attentionCount == 1
          ? '1 thing needs attention'
          : '$attentionCount things need attention';
    }
    if (unknownCount > 0) return 'Almost there — one thing to double-check';
    return 'You\'re all set';
  }
}
