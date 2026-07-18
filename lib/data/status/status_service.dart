import 'dart:async';

import '../../domain/crew_status.dart';

/// Publishes the signed-in user's status and streams their crew's live statuses.
/// Production is `SupabaseStatusService` (Realtime); tests use [FakeStatusService];
/// unconfigured/signed-out uses [DisabledStatusService].
abstract interface class StatusService {
  /// Emits the current `userId -> status` map on listen and on every change.
  Stream<Map<String, CrewStatus>> watch();

  Map<String, CrewStatus> get current;

  /// Upserts the signed-in user's own status. Best-effort — callers do not
  /// depend on it and it must never throw into the alarm path.
  Future<void> publish(CrewStatus status);
}

/// In-memory [StatusService] for tests. [initial] seeds the crew map;
/// [publish] just records the value; [emitStatus] simulates a Realtime push.
class FakeStatusService implements StatusService {
  FakeStatusService({Map<String, CrewStatus> initial = const {}})
      : _statuses = {...initial};

  final Map<String, CrewStatus> _statuses;
  final StreamController<Map<String, CrewStatus>> _controller =
      StreamController<Map<String, CrewStatus>>.broadcast();

  CrewStatus? lastPublished;
  int publishCount = 0;

  @override
  Map<String, CrewStatus> get current => Map.unmodifiable(_statuses);

  @override
  Stream<Map<String, CrewStatus>> watch() async* {
    yield Map.unmodifiable(_statuses);
    yield* _controller.stream;
  }

  @override
  Future<void> publish(CrewStatus status) async {
    lastPublished = status;
    publishCount++;
  }

  /// Test helper: simulate a crew member's status arriving over Realtime.
  void emitStatus(String userId, CrewStatus status) {
    _statuses[userId] = status;
    _controller.add(Map.unmodifiable(_statuses));
  }

  Future<void> dispose() => _controller.close();
}

/// Used when unconfigured/signed-out: no statuses, publish is a harmless no-op.
class DisabledStatusService implements StatusService {
  const DisabledStatusService();

  @override
  Map<String, CrewStatus> get current => const {};

  @override
  Stream<Map<String, CrewStatus>> watch() =>
      Stream.value(const <String, CrewStatus>{});

  @override
  Future<void> publish(CrewStatus status) async {}
}
