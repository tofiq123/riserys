/// Sends a "wake up" nudge (a push) to a crew member. Production is
/// `SupabaseNudgeService` (invokes the send-nudge edge function); tests use
/// [FakeNudgeService]; unconfigured/signed-out uses [DisabledNudgeService].
abstract interface class NudgeService {
  /// Sends a nudge to [userId]. Best-effort — throws [NudgeException] with a
  /// user-facing message on a rejection (rate-limited, not crew, offline).
  Future<void> nudge(String userId);
}

/// A nudge could not be sent; [message] is user-facing.
class NudgeException implements Exception {
  const NudgeException(this.message);
  final String message;
  @override
  String toString() => 'NudgeException: $message';
}

/// In-memory [NudgeService] for tests: records the last nudged id + count, or
/// throws [NudgeException] with [failWith] when set.
class FakeNudgeService implements NudgeService {
  FakeNudgeService({this.failWith});

  final String? failWith;

  String? lastNudged;
  int nudgeCount = 0;

  @override
  Future<void> nudge(String userId) async {
    if (failWith != null) throw NudgeException(failWith!);
    lastNudged = userId;
    nudgeCount++;
  }
}

/// Used when unconfigured/signed-out: nudge is a harmless no-op.
class DisabledNudgeService implements NudgeService {
  const DisabledNudgeService();

  @override
  Future<void> nudge(String userId) async {}
}
