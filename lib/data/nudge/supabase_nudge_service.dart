import 'package:supabase_flutter/supabase_flutter.dart';

import 'nudge_service.dart';

/// Production [NudgeService]: invokes the `send-nudge` edge function, which
/// verifies crew membership + rate limits, then pushes to the target's devices
/// via FCM. Only constructed when configured, and only off the alarm path.
///
/// NOTE: build-verified only (needs a live backend + FCM). Exercised by the
/// two-device nudge smoke test in the 5d setup guide.
class SupabaseNudgeService implements NudgeService {
  SupabaseNudgeService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<void> nudge(String userId, {NudgeKind kind = NudgeKind.nudge}) async {
    try {
      // Only the target id + the kind's wire name cross the wire. The push
      // copy is composed by the edge function — never send message text here.
      await _client.functions.invoke('send-nudge', body: {
        'to': userId,
        'kind': kind.wire,
      });
    } on FunctionException catch (e) {
      // The function returns a 4xx with {"error": "..."} for a rejection
      // (rate-limited, not crew). Surface that message; else a generic one.
      final details = e.details;
      final message = (details is Map && details['error'] != null)
          ? details['error'].toString()
          : 'Could not send the nudge. Try again.';
      throw NudgeException(message);
    }
  }
}
