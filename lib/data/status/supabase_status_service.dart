import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/crew_status.dart';
import 'status_service.dart';

/// Production [StatusService]: upserts the signed-in user's status and streams
/// the crew's live statuses via Supabase Realtime (RLS delivers only the
/// caller's own + accepted-friends' rows). Only constructed when configured,
/// and only off the alarm path.
///
/// NOTE: build-verified only (Realtime needs a live backend). Exercised by the
/// two-account live-status smoke test in the 5c setup guide.
class SupabaseStatusService implements StatusService {
  SupabaseStatusService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client {
    _authSub = _client.auth.onAuthStateChange.listen((state) {
      if (state.session?.user == null) {
        _teardownChannel();
        _statuses = {};
        _emit();
      } else {
        unawaited(_start());
      }
    });
  }

  final SupabaseClient _client;
  final StreamController<Map<String, CrewStatus>> _controller =
      StreamController<Map<String, CrewStatus>>.broadcast();
  StreamSubscription<AuthState>? _authSub;
  RealtimeChannel? _channel;
  Map<String, CrewStatus> _statuses = {};

  @override
  Map<String, CrewStatus> get current => Map.unmodifiable(_statuses);

  @override
  Stream<Map<String, CrewStatus>> watch() async* {
    yield Map.unmodifiable(_statuses);
    yield* _controller.stream;
  }

  void _emit() {
    if (!_controller.isClosed) _controller.add(Map.unmodifiable(_statuses));
  }

  CrewStatus _parse(Object? raw) => CrewStatus.values.firstWhere(
        (v) => v.name == raw,
        orElse: () => CrewStatus.unknown,
      );

  /// Initial fetch (RLS-scoped) then subscribe to live changes.
  Future<void> _start() async {
    try {
      final rows = await _client.from('statuses').select('user_id, status');
      _statuses = {
        for (final r in rows) r['user_id'] as String: _parse(r['status']),
      };
      _emit();
    } catch (_) {
      // best-effort; leave whatever we had
    }
    _subscribe();
  }

  void _subscribe() {
    _teardownChannel();
    final channel = _client.channel('public:statuses');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'statuses',
      callback: (payload) {
        final record =
            payload.newRecord.isNotEmpty ? payload.newRecord : payload.oldRecord;
        final userId = record['user_id'] as String?;
        if (userId == null) return;
        if (payload.eventType == PostgresChangeEvent.delete) {
          _statuses.remove(userId);
        } else {
          _statuses[userId] = _parse(record['status']);
        }
        _emit();
      },
    ).subscribe();
    _channel = channel;
  }

  void _teardownChannel() {
    final channel = _channel;
    if (channel != null) {
      unawaited(_client.removeChannel(channel));
      _channel = null;
    }
  }

  @override
  Future<void> publish(CrewStatus status) async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return; // not signed in — nothing to publish
    try {
      await _client.from('statuses').upsert({
        'user_id': me,
        'status': status.name,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id');
    } catch (_) {
      // best-effort; a publish failure must never surface to the caller
    }
  }

  /// Cancels the auth subscription, removes the channel, closes the stream.
  Future<void> dispose() async {
    await _authSub?.cancel();
    _teardownChannel();
    await _controller.close();
  }
}
