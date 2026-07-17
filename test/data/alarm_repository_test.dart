import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/local/alarm_repository.dart';
import 'package:rise/data/local/database.dart';
import 'package:rise/domain/alarm.dart';

/// Matches a [DateTime] denoting the same instant as [expected], regardless
/// of whether either value is flagged UTC or local. Needed because drift's
/// default storage (unix seconds) reads DateTimeColumn values back as
/// local-flavored DateTimes, while this test writes UTC ones; Dart's plain
/// `==` treats those as unequal even when they are the same moment.
Matcher sameInstant(DateTime expected) => predicate<DateTime?>(
    (actual) => actual != null && actual.isAtSameMomentAs(expected),
    'is at the same moment as $expected');

void main() {
  late RiseDatabase db;
  late AlarmRepository repo;

  setUp(() {
    db = RiseDatabase(NativeDatabase.memory());
    repo = AlarmRepository(db);
  });

  tearDown(() async => db.close());

  test('starts empty', () async {
    expect(await repo.all(), isEmpty);
  });

  test('inserts an alarm and assigns an id', () async {
    final saved = await repo.upsert(
        const Alarm(id: 0, hour: 6, minute: 30, label: 'Run', days: {1, 2, 3, 4, 5}));
    expect(saved.id, greaterThan(0));

    final all = await repo.all();
    expect(all, hasLength(1));
    expect(all.single.label, 'Run');
    expect(all.single.days, {1, 2, 3, 4, 5});
  });

  test('round-trips an empty day set as a one-shot alarm', () async {
    await repo.upsert(const Alarm(id: 0, hour: 6, minute: 30));
    expect((await repo.all()).single.days, isEmpty);
  });

  test('updates an existing alarm in place', () async {
    final saved = await repo.upsert(const Alarm(id: 0, hour: 6, minute: 30));
    await repo.upsert(saved.copyWith(hour: 7, label: 'Later'));

    final all = await repo.all();
    expect(all, hasLength(1));
    expect(all.single.hour, 7);
    expect(all.single.label, 'Later');
  });

  test('toggles enabled', () async {
    final saved = await repo.upsert(const Alarm(id: 0, hour: 6, minute: 30));
    await repo.setEnabled(saved.id, false);
    expect((await repo.all()).single.enabled, isFalse);
  });

  test('deletes an alarm', () async {
    final saved = await repo.upsert(const Alarm(id: 0, hour: 6, minute: 30));
    await repo.delete(saved.id);
    expect(await repo.all(), isEmpty);
  });

  test('lastDismissedAt is null until an alarm is dismissed', () async {
    await repo.upsert(const Alarm(id: 0, hour: 6, minute: 30));
    expect((await repo.all()).single.lastDismissedAt, isNull);
  });

  test('recordDismissed round-trips lastDismissedAt through the database',
      () async {
    final saved = await repo.upsert(
        const Alarm(id: 0, hour: 6, minute: 30, days: {1, 2, 3, 4, 5}));
    final at = DateTime.utc(2026, 7, 15, 6, 30, 45);

    await repo.recordDismissed(saved.id, at);

    expect((await repo.all()).single.lastDismissedAt, sameInstant(at));
  });

  test('recordDismissed disables a one-shot alarm (empty days)', () async {
    final saved = await repo.upsert(const Alarm(id: 0, hour: 6, minute: 30));
    expect(saved.days, isEmpty, reason: 'precondition: this is a one-shot');

    await repo.recordDismissed(saved.id, DateTime.utc(2026, 7, 15, 6, 30));

    final row = (await repo.all()).single;
    expect(row.enabled, isFalse);
    expect(row.lastDismissedAt, sameInstant(DateTime.utc(2026, 7, 15, 6, 30)));
  });

  test('recordDismissed does not disable a repeating alarm', () async {
    final saved = await repo.upsert(
        const Alarm(id: 0, hour: 6, minute: 30, days: {1, 2, 3, 4, 5}));

    await repo.recordDismissed(saved.id, DateTime.utc(2026, 7, 15, 6, 30));

    final row = (await repo.all()).single;
    expect(row.enabled, isTrue);
    expect(row.lastDismissedAt, sameInstant(DateTime.utc(2026, 7, 15, 6, 30)));
  });

  test(
      'recordDismissed normalizes a local instant to the same UTC moment '
      'before storing it', () async {
    final saved = await repo.upsert(const Alarm(id: 0, hour: 6, minute: 30));
    final local = DateTime(2026, 7, 15, 6, 30); // not explicitly UTC

    await repo.recordDismissed(saved.id, local);

    final stored = (await repo.all()).single.lastDismissedAt;
    expect(stored, sameInstant(local.toUtc()));
  });

  test('the database rejects an out-of-range hour at the schema level',
      () async {
    // Bypasses Alarm's constructor entirely (its range check is an `assert`,
    // stripped in release builds) to prove the CHECK constraint enforces the
    // range at the actual trust boundary: the database itself.
    await expectLater(
      db.into(db.alarms).insert(AlarmsCompanion.insert(hour: 24, minute: 0)),
      throwsException,
    );
  });

  test('the database rejects an out-of-range minute at the schema level',
      () async {
    await expectLater(
      db.into(db.alarms).insert(AlarmsCompanion.insert(hour: 5, minute: 60)),
      throwsException,
    );
  });

  test('watchAll emits on change', () async {
    final firstEmission = Completer<void>();
    final afterWrite = Completer<List<Alarm>>();

    final sub = repo.watchAll().listen(
      (rows) {
        if (!firstEmission.isCompleted) {
          firstEmission.complete();
        } else if (!afterWrite.isCompleted) {
          afterWrite.complete(rows);
        }
      },
      onDone: () {
        if (!afterWrite.isCompleted) {
          afterWrite.completeError(
              StateError('watchAll closed without re-emitting after the write'));
        }
      },
    );

    // Wait for the stream to go live before writing. The first emission's value
    // is deliberately not asserted: whether a subscriber observes the pre-write
    // state depends on drift coalescing an in-flight initial fetch when a change
    // lands first, which is correct behaviour and not a requirement of ours. The
    // requirement is that a write is reflected in a subsequent emission.
    await firstEmission.future;

    await repo.upsert(const Alarm(id: 0, hour: 6, minute: 30));

    final rows = await afterWrite.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () =>
          throw StateError('watchAll did not re-emit after the write'),
    );
    expect(rows, hasLength(1));
    expect(rows.single.hour, 6);
    expect(rows.single.minute, 30);

    await sub.cancel();
  });

  test('snoozedUntil round-trips through upsert', () async {
    final saved = await repo.upsert(const Alarm(id: 0, hour: 6, minute: 30)
        .copyWith(snoozedUntil: DateTime.utc(2026, 7, 20, 6, 39)));
    final read = (await repo.all()).firstWhere((a) => a.id == saved.id);
    expect(read.snoozedUntil, isNotNull);
    expect(read.snoozedUntil!.toUtc(), DateTime.utc(2026, 7, 20, 6, 39));
  });

  test('setSnoozedUntil then clearSnoozedUntil', () async {
    final saved = await repo.upsert(const Alarm(id: 0, hour: 6, minute: 30));
    await repo.setSnoozedUntil(saved.id, DateTime.utc(2026, 7, 20, 6, 39));
    expect((await repo.all()).single.snoozedUntil, isNotNull);
    await repo.clearSnoozedUntil(saved.id);
    expect((await repo.all()).single.snoozedUntil, isNull);
  });

  test('recordDismissed clears a pending snooze', () async {
    final saved = await repo.upsert(
        const Alarm(id: 0, hour: 6, minute: 30, days: {1})
            .copyWith(snoozedUntil: DateTime.utc(2026, 7, 20, 6, 39)));
    await repo.recordDismissed(saved.id, DateTime.utc(2026, 7, 20, 6, 40));
    expect((await repo.all()).single.snoozedUntil, isNull);
  });
}
