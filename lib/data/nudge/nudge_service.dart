/// Sends a typed crew push (a nudge, by default) to a crew member. Production
/// is `SupabaseNudgeService` (invokes the send-nudge edge function); tests use
/// [FakeNudgeService]; unconfigured/signed-out uses [DisabledNudgeService].
abstract interface class NudgeService {
  /// Sends a push of [kind] to [userId]. Best-effort — throws [NudgeException]
  /// with a user-facing message on a rejection (rate-limited, not crew,
  /// offline).
  Future<void> nudge(String userId, {NudgeKind kind = NudgeKind.nudge});
}

/// The typed reason for a push, sent to the send-nudge edge function as its
/// `kind` body param.
///
/// SECURITY: this enum is the ONLY thing the client contributes to a push —
/// the notification title/body are composed SERVER-side from a fixed copy map
/// keyed by kind. Never add a free-text message parameter here: that would be
/// a push-injection vector.
enum NudgeKind {
  /// Crew "wake up" nudge (the default — matches the pre-typed behavior).
  nudge,

  /// A voice clip just landed ("open Rise to listen").
  voice,

  /// Accountability ping ("slipped today and is back on it").
  backup,

  /// Crew SOS ("can't wake up — give them a shout").
  sos;

  /// The wire value the edge function's allowlist accepts.
  String get wire => name;

  /// Parses a wire value, mirroring the server's allowlist guard: an unknown
  /// value is REJECTED (the server 400s it), never coerced to a default.
  static NudgeKind fromWire(String value) => values.firstWhere(
        (k) => k.wire == value,
        orElse: () =>
            throw ArgumentError.value(value, 'value', 'unknown nudge kind'),
      );
}

/// A nudge could not be sent; [message] is user-facing.
class NudgeException implements Exception {
  const NudgeException(this.message);
  final String message;
  @override
  String toString() => 'NudgeException: $message';
}

/// In-memory [NudgeService] for tests: records the last nudged id + kind +
/// count, or throws [NudgeException] with [failWith] when set.
class FakeNudgeService implements NudgeService {
  FakeNudgeService({this.failWith});

  final String? failWith;

  String? lastNudged;
  NudgeKind? lastKind;
  int nudgeCount = 0;

  @override
  Future<void> nudge(String userId, {NudgeKind kind = NudgeKind.nudge}) async {
    if (failWith != null) throw NudgeException(failWith!);
    lastNudged = userId;
    lastKind = kind;
    nudgeCount++;
  }
}

/// Used when unconfigured/signed-out: nudge is a harmless no-op.
class DisabledNudgeService implements NudgeService {
  const DisabledNudgeService();

  @override
  Future<void> nudge(String userId, {NudgeKind kind = NudgeKind.nudge}) async {}
}

/// Best-effort fan-out of a [kind] push to every id in [memberIds]. Per-member
/// failures are swallowed — one member with no device token (or a transient
/// error) must not stop the rest, and the send-nudge function rate-limits
/// duplicates server-side. Returns how many sends were accepted. Used by the
/// Crew SOS (manual + auto) and reusable for any "tell the whole crew" action.
Future<int> pingCrew(
  NudgeService nudge,
  Iterable<String> memberIds,
  NudgeKind kind,
) async {
  var sent = 0;
  for (final id in memberIds) {
    try {
      await nudge.nudge(id, kind: kind);
      sent++;
    } catch (_) {}
  }
  return sent;
}
