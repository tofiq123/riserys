import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/wake_event_repository.dart';
import '../../data/wake_recorder.dart';
import '../../domain/streak.dart';
import '../../domain/wake_event.dart';
import 'alarm_providers.dart';

/// The wake-event store, built over the same database handle the alarm
/// repository uses.
final wakeEventRepositoryProvider = Provider<WakeEventRepository>(
    (ref) => WakeEventRepository(ref.watch(alarmRepositoryProvider).database));

final wakeRecorderProvider = Provider<WakeRecorder>((ref) => WakeRecorder(
    ref.watch(wakeEventRepositoryProvider), ref.watch(alarmRepositoryProvider)));

final wakeEventsProvider = StreamProvider<List<WakeEvent>>(
    (ref) => ref.watch(wakeEventRepositoryProvider).watchAll());

/// The streak recomputed from the live event log.
final streakProvider = Provider<StreakStats>((ref) {
  final events = ref.watch(wakeEventsProvider).value ?? const <WakeEvent>[];
  return computeStreak(events, DateTime.now());
});
