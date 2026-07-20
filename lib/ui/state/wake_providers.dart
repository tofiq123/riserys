import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/excused_days_repository.dart';
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

/// The "rough night" days the user excused, built over the same database handle.
final excusedDaysRepositoryProvider = Provider<ExcusedDaysRepository>((ref) =>
    ExcusedDaysRepository(ref.watch(alarmRepositoryProvider).database));

/// The live set of excused (rough-night) local-midnight days.
final excusedDaysProvider = StreamProvider<Set<DateTime>>(
    (ref) => ref.watch(excusedDaysRepositoryProvider).watchAll());

/// The streak recomputed from the live event log, with any excused rough-night
/// days held (they neither break nor advance the streak).
final streakProvider = Provider<StreakStats>((ref) {
  final events = ref.watch(wakeEventsProvider).value ?? const <WakeEvent>[];
  // Excused days are additive and best-effort: if their store is unavailable
  // (e.g. before the DB is configured), fall back to none rather than letting
  // the streak readout throw everywhere it is shown. Mirrors the resilience of
  // currentSettingsProvider.
  Set<DateTime> excused;
  try {
    excused = ref.watch(excusedDaysProvider).value ?? const <DateTime>{};
  } catch (_) {
    excused = const <DateTime>{};
  }
  return computeStreak(events, DateTime.now(), excusedDays: excused);
});
