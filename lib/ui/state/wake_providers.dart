import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/excused_days_repository.dart';
import '../../data/local/wake_event_repository.dart';
import '../../data/wake_recorder.dart';
import '../../domain/streak.dart';
import '../../domain/wake_event.dart';
import '../../domain/wake_evidence.dart';
import 'alarm_providers.dart';
import 'home_providers.dart';

/// The wake-event store, built over the same database handle the alarm
/// repository uses.
final wakeEventRepositoryProvider = Provider<WakeEventRepository>(
    (ref) => WakeEventRepository(ref.watch(alarmRepositoryProvider).database));

final wakeRecorderProvider = Provider<WakeRecorder>((ref) => WakeRecorder(
      ref.watch(wakeEventRepositoryProvider),
      ref.watch(alarmRepositoryProvider),
      // A new alarm ringing begins a fresh wake day: clear yesterday's
      // "left home" evidence so a stale flag can't publish "up & out" or
      // colour today's evidence card until a new positive fix is taken.
      onRingOpened: () =>
          ref.read(leftHomeTodayProvider.notifier).state = false,
    ));

final wakeEventsProvider = StreamProvider<List<WakeEvent>>(
    (ref) => ref.watch(wakeEventRepositoryProvider).watchAll());

/// The "rough night" days the user excused, built over the same database handle.
final excusedDaysRepositoryProvider = Provider<ExcusedDaysRepository>((ref) =>
    ExcusedDaysRepository(ref.watch(alarmRepositoryProvider).database));

/// The live set of excused (rough-night) local-midnight days.
final excusedDaysProvider = StreamProvider<Set<DateTime>>(
    (ref) => ref.watch(excusedDaysRepositoryProvider).watchAll());

/// The wake-evidence "user card" for the most recent COMPLETED wake, or null
/// when there is nothing to summarise yet. Fuses the morning's many signals
/// (timing, method, snoozes, mission slips, alertness) with today's opt-in
/// left-home verdict into a single warm read. Recomputes when the event log or
/// the left-home flag changes.
final wakeEvidenceProvider = Provider<WakeEvidence?>((ref) {
  final events = ref.watch(wakeEventsProvider).value ?? const <WakeEvent>[];
  WakeEvent? latest;
  for (final e in events) {
    if (e.isOpen) continue; // only a finished wake can be summarised
    if (latest == null || e.firstRingAt.isAfter(latest.firstRingAt)) latest = e;
  }
  return WakeEvidence.of(latest, leftHome: ref.watch(leftHomeTodayProvider));
});

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
